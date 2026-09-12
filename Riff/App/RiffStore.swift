import SwiftUI
import AVFoundation
import Observation

@MainActor @Observable final class RiffStore {
    let updates = CompanionUpdates()
    var installingPackID: String?
    var packInstallProgress = 0
    var packInstallStatus = ""
    var packInstallError: String?
    private var packInstallTask: Task<Void, Never>?
    var supportsPacks: Bool { snapshot.capabilities?.contains("sound-packs-v1") == true }

    func installPack(_ pack: SoundPack) {
        guard packInstallTask == nil, !busy, let client, connected, supportsPacks else { return }
        let missing = pack.sounds.count - pack.installed(in: snapshot.clips).count
        guard snapshot.clips.count + missing <= 500 else {
            packInstallError = "This pack needs \(missing) library spaces. Remove some sounds from your PC library, then try again."
            return
        }
        busy = true; epoch += 1
        let generation = epoch
        installingPackID = pack.id; packInstallError = nil
        packInstallProgress = pack.installed(in: snapshot.clips).count
        packInstallTask = Task {
            defer { busy = false; installingPackID = nil; packInstallTask = nil; packInstallStatus = "" }
            do {
                for sound in pack.sounds {
                    try Task.checkCancellation()
                    guard generation == epoch, connected else { throw RiffError.message("Reconnect your PC, then resume this pack.") }
                    if snapshot.clips.contains(where: { $0.id == sound.clipID }) { continue }
                    let data = try SoundPacks.audioData(for: sound)
                    packInstallStatus = "Saving \(sound.name) to PC…"
                    let next: Snapshot = try await client.request("/api/packs/\(pack.id)/sounds/\(sound.id)", method: "POST", body: data, contentType: "application/octet-stream")
                    guard generation == epoch, connected else { throw RiffError.message("Reconnect your PC, then resume this pack.") }
                    apply(next)
                    packInstallProgress = pack.installed(in: snapshot.clips).count
                }
                message("\(pack.name) added to PC. Add it to a deck to start playing.")
            } catch {
                let cancelled = Task.isCancelled
                // Refresh after an interrupted upload; the PC may have saved it before the response was lost.
                if generation == epoch, let next: Snapshot = try? await client.request("/api/state") { apply(next) }
                if cancelled { message("Transfer paused. Sounds already on your PC are kept.") }
                else { packInstallError = "\(error.localizedDescription) Sounds already on your PC are kept; resume to finish copying the pack." }
            }
        }
    }
    func cancelPackInstall() { packInstallTask?.cancel() }

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
    private var players: [String: AVAudioPlayer] = [:]
    private var previewPlayer: AVAudioPlayer?
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = UUID()
    var isPreviewPlaying: Bool { previewPlayer?.isPlaying == true }
    private var playback = SoundPlaybackTracker()
    private var playbackRefreshRunning = false
    var playingPadIDs: Set<String> = []
    var soundMode = SoundPlaybackMode(rawValue: UserDefaults.standard.string(forKey: "soundMode") ?? "") ?? .overlap {
        didSet { UserDefaults.standard.set(soundMode.rawValue, forKey: "soundMode") }
    }
    var supportsPlayback: Bool { snapshot.capabilities?.contains("soundboard-playback-v1") == true }
    private func stopLocalSounds() {
        stopPreview()
        for player in players.values { player.stop() }
        players.removeAll(); playingPadIDs.removeAll()
    }
    private func acceptPlayback(_ next: SoundPlaybackState?) {
        guard let next else { return }
        playback.accept(next); playingPadIDs = playback.padIDs
    }
    func refreshPlayback() async {
        if !connected {
            players = players.filter { $0.value.isPlaying }
            playingPadIDs = Set(players.keys)
            return
        }
        guard supportsPlayback, let client, !playbackRefreshRunning else { return }
        playbackRefreshRunning = true; let generation = epoch
        defer { playbackRefreshRunning = false }
        do {
            let state: SoundPlaybackState = try await client.request("/api/playback")
            guard generation == epoch, connected else { return }
            acceptPlayback(state)
        } catch {
            if generation == epoch { playingPadIDs.removeAll() }
        }
    }
    private var lastGame = ""
    private var toastTask: Task<Void, Never>?
    private var refreshRunning = false
    private var epoch = 0
    private var cachedData: Data?
    private let snapshotCacheURL: URL
    var selectedDeck: Deck? { snapshot.decks.first { $0.id == selectedDeckId } }
    var paired: Bool { client != nil }
    var outputName: String { snapshot.outputs.first { $0.id == snapshot.outputId }?.name ?? "PC default output" }
    var cableSelected: Bool { outputName.localizedCaseInsensitiveContains("cable") || outputName.localizedCaseInsensitiveContains("voicemeeter") }

    convenience init() { self.init(cacheURL: Self.cacheURL, pairing: PairingVault.load()) }

    init(cacheURL: URL, pairing: Pairing?) {
        snapshotCacheURL = cacheURL
        if let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) { snapshot = saved; cachedData = data }
        if selectedDeck == nil { selectedDeckId = snapshot.decks.first?.id ?? "" }
        if let pairing { client = CompanionClient(pairing: pairing) }
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
        stopLocalSounds(); playback = SoundPlaybackTracker()
        epoch += 1; client = next; apply(state); connected = true; connectionIssue = nil
        message("Connected to \(state.computerName)")
    }
    func disconnect() {
        cancelPackInstall()
        epoch += 1; client = nil; connected = false; connectionIssue = nil; PairingVault.delete(); stopLocalSounds(); playback = SoundPlaybackTracker()
    }
    func refresh() async {
        guard let client, !busy, !connecting, !refreshRunning else { return }
        refreshRunning = true; let generation = epoch
        defer { refreshRunning = false }
        do {
            let state: Snapshot = try await client.request("/api/state")
            guard generation == epoch, !busy else { return }
            if !connected { stopLocalSounds() }
            apply(state); connected = true; connectionIssue = nil
        } catch {
            if generation == epoch {
                connected = false; playingPadIDs.removeAll()
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
            try FileManager.default.createDirectory(at: snapshotCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            if data != cachedData { try data.write(to: snapshotCacheURL, options: .atomic); cachedData = data }
        } catch { /* Cache is optional; the companion remains authoritative. */ }
    }
    func trigger(_ pad: Pad) async {
        if !connected {
            guard pad.kind == "sound", let url = SoundPacks.audioURL(forClipID: pad.value) ?? Bundle.main.url(forResource: pad.value, withExtension: "wav") else {
                error = "Connect your PC to use this action."; return
            }
            do {
#if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
#endif
                players = players.filter { $0.value.isPlaying }
                if let playing = players.removeValue(forKey: pad.id) {
                    playing.stop(); playingPadIDs = Set(players.keys)
                    message("Stopped \(pad.title)"); return
                }
                if soundMode == .single { stopLocalSounds() }
                guard players.count < 16 else { throw RiffError.message("16 sounds are already playing. Stop a sound before starting another.") }
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = snapshot.volume
                guard player.play() else { throw RiffError.message("This sound could not be played.") }
                players[pad.id] = player; playingPadIDs = Set(players.keys)
                message("Playing on iPad: \(pad.title)")
            } catch { self.error = error.localizedDescription }
            return
        }
        guard let client else { return }
        let generation = epoch
        activePad = pad.id
        defer { if activePad == pad.id { activePad = nil } }
        do {
            struct Trigger: Encodable { let padId: String; let requestId: String; let toggle: Bool?; let soundMode: String? }
            let result: Acknowledgement = try await client.request("/api/trigger", method: "POST", body: JSONEncoder().encode(Trigger(padId: pad.id, requestId: UUID().uuidString, toggle: supportsPlayback ? true : nil, soundMode: supportsPlayback ? soundMode.rawValue : nil)))
            guard generation == epoch, connected else { return }
            acceptPlayback(result.playback)
            if pad.kind != "sound" || !supportsPlayback { message("\(pad.title) sent to PC") }
        } catch { self.error = "\(error.localizedDescription) The action was not retried, to avoid playing it twice." }
    }
    func stopAll() async {
        stopLocalSounds()
        guard let client, connected else { message("Preview stopped"); return }
        let generation = epoch
        do {
            let result: Acknowledgement = try await client.request("/api/stop", method: "POST")
            guard generation == epoch, connected else { return }
            acceptPlayback(result.playback)
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
        guard !busy else { throw RiffError.message("Wait for the current change to finish.") }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 20 * 1024 * 1024 {
            throw RiffError.message("Choose a sound smaller than 20 MB.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 20 * 1024 * 1024 else { throw RiffError.message("Choose a sound smaller than 20 MB.") }
        busy = true; epoch += 1
        let generation = epoch
        defer { busy = false }
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "ext", value: url.pathExtension.lowercased())]
        let clip: Clip = try await client.request("/api/clips?\(query.percentEncodedQuery ?? "")", method: "POST", body: data, contentType: "application/octet-stream")
        guard generation == epoch else { throw RiffError.message("The PC connection changed while saving. Reconnect and check Sounds for your clip.") }
        do {
            // An older poll may still be in flight. Fetch the post-upload version directly.
            let state: Snapshot = try await client.request("/api/state")
            guard generation == epoch else { throw CancellationError() }
            apply(state)
        } catch {
            guard generation == epoch else { throw RiffError.message("The PC connection changed. Reconnect and check Sounds for your saved clip.") }
            // The upload succeeded. Keep its result instead of asking the user to upload twice.
            if !snapshot.clips.contains(where: { $0.id == clip.id }) { snapshot.clips.append(clip) }
            connected = false
            connectionIssue = "Your sound was saved on the PC. Reconnect to finish adding its button."
            message("Sound saved on PC. Reconnecting…")
        }
        return clip
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
    func stopPreview() {
        previewGeneration = UUID()
        previewTask?.cancel(); previewTask = nil
        previewPlayer?.stop(); previewPlayer = nil
    }
    func preview(_ clip: Clip) async {
        stopPreview()
        let generation = previewGeneration
        let task = Task {
            defer { if generation == previewGeneration { previewTask = nil } }
            do {
                let data: Data
                if let url = SoundPacks.audioURL(forClipID: clip.id) ?? Bundle.main.url(forResource: clip.id, withExtension: "wav") {
                    data = try Data(contentsOf: url)
                } else if let client, connected, snapshot.capabilities?.contains("clip-audio-v1") == true {
                    let id = clip.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
                    data = try await client.requestData("/api/clips/\(id)/audio")
                } else {
                    throw RiffError.message(connected
                        ? "Update Riff on your PC to preview imported and recorded sounds on this iPad."
                        : "Connect your PC to preview this sound on your iPad.")
                }
                try Task.checkCancellation()
                guard generation == previewGeneration else { return }
#if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
#endif
                let player = try AVAudioPlayer(data: data)
                guard player.play() else { throw RiffError.message("This preview could not be played.") }
                previewPlayer = player
                message("Playing on iPad: \(clip.name)")
            } catch {
                if !Task.isCancelled && generation == previewGeneration { self.error = error.localizedDescription }
            }
        }
        previewTask = task
        await task.value
    }
    func testSoundOnPC(_ clip: Clip) async {
        if let client, connected {
            do {
                let generation = epoch
                struct Preview: Encodable { let clipId: String; let soundMode: String? }
                let result: Acknowledgement = try await client.request("/api/preview", method: "POST", body: JSONEncoder().encode(Preview(clipId: clip.id, soundMode: supportsPlayback ? soundMode.rawValue : nil)))
                guard generation == epoch, connected else { return }
                acceptPlayback(result.playback)
                message("Playing on PC: \(clip.name)")
            } catch { self.error = error.localizedDescription }
        } else { error = "Connect your PC to test its audio output." }
    }
}
struct Acknowledgement: Decodable { let ok: Bool; let playback: SoundPlaybackState? }
