import SwiftUI
import AVFoundation
import Observation

@MainActor @Observable final class RiffStore {
    var snapshot = Snapshot.starter
    var selectedDeckId = "soundboard"
    var connected = false
    var connecting = false
    var connectionIssue: String?
    var busy = false
    var error: String?
    var toast: String?
    var activePad: String?
    var editing = false
    var interacting = false
    private(set) var favoriteClipIDs = Set(UserDefaults.standard.stringArray(forKey: "favoriteClipIDs") ?? []) {
        didSet { UserDefaults.standard.set(favoriteClipIDs.sorted(), forKey: "favoriteClipIDs") }
    }
    func toggleFavorite(_ clip: Clip) {
        if favoriteClipIDs.contains(clip.id) { favoriteClipIDs.remove(clip.id) }
        else { favoriteClipIDs.insert(clip.id) }
    }
    var autoSwitch = UserDefaults.standard.object(forKey: "autoSwitch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSwitch, forKey: "autoSwitch") }
    }
    private var gridLayouts: [String: GridPreferences] = {
        guard let data = UserDefaults.standard.data(forKey: "gridLayouts"),
              let saved = try? JSONDecoder().decode([String: GridPreferences].self, from: data) else { return [:] }
        return saved
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(gridLayouts) { UserDefaults.standard.set(data, forKey: "gridLayouts") }
        }
    }
    var grid: GridPreferences {
        get { gridLayouts[selectedDeckId] ?? GridPreferences(columns: UserDefaults.standard.integer(forKey: "columns")) }
        set { gridLayouts[selectedDeckId] = newValue }
    }
    private var client: CompanionClient?
    private var player: AVAudioPlayer?
    private var lastGame = ""
    private var toastTask: Task<Void, Never>?
    private var refreshRunning = false
    private var epoch = 0
    private var cachedData: Data?
    var selectedDeck: Deck? { snapshot.decks.first { $0.id == selectedDeckId } }
    var paired: Bool { client != nil }
    var outputName: String { snapshot.outputs.first { $0.id == snapshot.outputId }?.name ?? "PC default output" }
    var cableSelected: Bool { outputName.localizedCaseInsensitiveContains("cable") || outputName.localizedCaseInsensitiveContains("voicemeeter") }

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) { snapshot = saved; cachedData = data }
        if let pairing = PairingVault.load() { client = CompanionClient(pairing: pairing) }
    }
    static var cacheURL: URL { URL.applicationSupportDirectory.appendingPathComponent("snapshot.json") }
    func message(_ text: String) {
        toastTask?.cancel(); toast = text
        toastTask = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { toast = nil } }
    }
    func pair(_ link: String) async throws {
        guard !busy, !connecting else { return }
        connecting = true; defer { connecting = false }
        let pairing = try Pairing.parse(link)
        let next = CompanionClient(pairing: pairing)
        let state: Snapshot = try await next.request("/api/state")
        try PairingVault.save(pairing)
        epoch += 1; client = next; apply(state); connected = true; connectionIssue = nil
        message("Connected to \(state.computerName)")
    }
    func disconnect() {
        epoch += 1; client = nil; connected = false; connectionIssue = nil; PairingVault.delete(); player?.stop()
    }
    func refresh() async {
        guard let client, !busy, !connecting, !refreshRunning else { return }
        refreshRunning = true; let generation = epoch
        defer { refreshRunning = false }
        do {
            let state: Snapshot = try await client.request("/api/state")
            guard generation == epoch, !busy else { return }
            apply(state); connected = true; connectionIssue = nil
        } catch {
            if generation == epoch {
                connected = false
                connectionIssue = error is RiffError ? error.localizedDescription : "Make sure Riff is open on your PC and both devices are on the same network."
            }
        }
    }
    private func apply(_ state: Snapshot) {
        snapshot = state
        if !state.decks.contains(where: { $0.id == selectedDeckId }) { selectedDeckId = state.decks.first?.id ?? "" }
        if autoSwitch, !editing, !interacting, !state.activeGameId.isEmpty, state.activeGameId != lastGame,
           let deck = state.decks.first(where: { $0.steamAppId == state.activeGameId }) {
            selectedDeckId = deck.id; message("Switched to \(deck.name)")
        }
        if !editing && !interacting { lastGame = state.activeGameId }
        do {
            try FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            if data != cachedData { try data.write(to: Self.cacheURL, options: .atomic); cachedData = data }
        } catch { /* Cache is optional; the companion remains authoritative. */ }
    }
    func trigger(_ pad: Pad) async {
        if !connected {
            guard pad.kind == "sound", let url = Bundle.main.url(forResource: pad.value, withExtension: "wav") else {
                error = "Connect your PC to use this action."; return
            }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
                player = try AVAudioPlayer(contentsOf: url); player?.volume = snapshot.volume; player?.play()
                message("Preview on iPad: \(pad.title)")
            } catch { self.error = error.localizedDescription }
            return
        }
        guard let client else { return }
        activePad = pad.id
        defer { if activePad == pad.id { activePad = nil } }
        do {
            struct Trigger: Encodable { let padId: String; let requestId: String }
            let _: Acknowledgement = try await client.request("/api/trigger", method: "POST", body: JSONEncoder().encode(Trigger(padId: pad.id, requestId: UUID().uuidString)))
            message("\(pad.title) sent to PC")
        } catch { self.error = "\(error.localizedDescription) The action was not retried, to avoid playing it twice." }
    }
    func stopAll() async {
        player?.stop()
        guard let client, connected else { message("Preview stopped"); return }
        do {
            let _: Acknowledgement = try await client.request("/api/stop", method: "POST")
            message("All sounds and sequences stopped")
        } catch { self.error = error.localizedDescription }
    }
    func saveDecks(_ decks: [Deck]) async throws {
        guard let client, connected else { throw RiffError.message("Connect your PC before editing your decks.") }
        guard !busy else { throw RiffError.message("Wait for the current change to finish.") }
        busy = true; epoch += 1; defer { busy = false }
        struct Update: Encodable { let version: Int; let decks: [Deck] }
        do {
            let state: Snapshot = try await client.request("/api/decks", method: "PUT", body: JSONEncoder().encode(Update(version: snapshot.version, decks: decks)))
            apply(state)
        } catch {
            if let fresh: Snapshot = try? await client.request("/api/state") { apply(fresh) }
            throw error
        }
    }
    func savePad(_ pad: Pad, in deckId: String) async throws {
        try await saveDecks(snapshot.decksSaving(pad, in: deckId))
        selectedDeckId = deckId
        message("Saved \(pad.title)")
    }
    func movePad(_ id: String, to target: String) async {
        var decks = snapshot.decks
        guard let d = decks.firstIndex(where: { $0.id == selectedDeckId }),
              let from = decks[d].pads.firstIndex(where: { $0.id == id }),
              let to = decks[d].pads.firstIndex(where: { $0.id == target }), from != to else { return }
        let pad = decks[d].pads.remove(at: from); decks[d].pads.insert(pad, at: to)
        do { try await saveDecks(decks) } catch { self.error = error.localizedDescription }
    }
    func audio(output: String, volume: Float) async throws {
        guard let client, connected else { throw RiffError.message("Connect your PC to change audio routing.") }
        guard !busy else { throw RiffError.message("Wait for the current change to finish.") }
        busy = true; epoch += 1; defer { busy = false }
        struct Settings: Encodable { let outputId: String; let volume: Float }
        let state: Snapshot = try await client.request("/api/audio", method: "PUT", body: JSONEncoder().encode(Settings(outputId: output, volume: volume)))
        apply(state)
    }
    func upload(_ url: URL, name: String) async throws -> Clip {
        guard let client, connected else { throw RiffError.message("Connect your PC before adding sounds.") }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 20 * 1024 * 1024 {
            throw RiffError.message("Choose a sound smaller than 20 MB.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 20 * 1024 * 1024 else { throw RiffError.message("Choose a sound smaller than 20 MB.") }
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "ext", value: url.pathExtension.lowercased())]
        let clip: Clip = try await client.request("/api/clips?\(query.percentEncodedQuery ?? "")", method: "POST", body: data, contentType: "application/octet-stream")
        await refresh(); return clip
    }
    func deleteClip(_ clip: Clip) async {
        guard let client, connected else { return }
        guard !busy else { error = "Wait for the current change to finish."; return }
        busy = true; epoch += 1; defer { busy = false }
        do {
            let state: Snapshot = try await client.request("/api/clips/\(clip.id)", method: "DELETE")
            apply(state); message("Sound deleted")
        } catch { self.error = error.localizedDescription }
    }
    func renameClip(_ clip: Clip, name: String) async throws {
        guard let client, connected else { throw RiffError.message("Connect your PC to rename sounds.") }
        guard !busy else { throw RiffError.message("Wait for the current change to finish.") }
        busy = true; epoch += 1; defer { busy = false }
        struct Rename: Encodable { let version: Int; let name: String }
        do {
            let state: Snapshot = try await client.request("/api/clips/\(clip.id)", method: "PUT", body: JSONEncoder().encode(Rename(version: snapshot.version, name: name)))
            apply(state); message("Sound renamed")
        } catch {
            if let fresh: Snapshot = try? await client.request("/api/state") { apply(fresh) }
            throw error
        }
    }
    func preview(_ clip: Clip) async {
        if let client, connected {
            do {
                struct Preview: Encodable { let clipId: String }
                let _: Acknowledgement = try await client.request("/api/preview", method: "POST", body: JSONEncoder().encode(Preview(clipId: clip.id)))
                message("Playing on PC: \(clip.name)")
            } catch { self.error = error.localizedDescription }
        } else { await trigger(Pad(title: clip.name, value: clip.id)) }
    }
}
struct Acknowledgement: Decodable { let ok: Bool }
