import SwiftUI
import AVFoundation
import Observation

@MainActor @Observable final class RiffStore {
    let updates = CompanionUpdates()
    var snapshot = Snapshot.starter
    var selectedDeckId = "soundboard" {
        didSet { if oldValue != selectedDeckId { deckHistory.removeAll() } }
    }
    private var deckHistory: [String] = []
    var canGoBack: Bool { deckHistory.contains { id in snapshot.decks.contains { $0.id == id } } }
    var supportsKeyLogic: Bool { !connected || snapshot.capabilities?.contains("key-logic-v1") == true }
    var supportsPinnedPads: Bool { !connected || snapshot.capabilities?.contains("pinned-pads-v1") == true }
    var supportsDeckActions: Bool { !connected || snapshot.capabilities?.contains("deck-actions-v1") == true }
    var supportsSmartProfiles: Bool { !connected || snapshot.capabilities?.contains("smart-profiles-v1") == true }
    var availableActionKinds: [ActionKind] { ActionKind.allCases.filter { !$0.needsDeckActions || supportsDeckActions } }
    var followApps = UserDefaults.standard.bool(forKey: "followApps") {
        didSet { UserDefaults.standard.set(followApps, forKey: "followApps") }
    }
    private var smartProfiles = SmartProfiles()
    private var switchTracker = SoundPlaybackTracker()
    var switchedPadIDs: Set<String> = []
    private func acceptSwitchState(_ state: SoundPlaybackState?) {
        guard let state else { return }
        switchTracker.accept(state); switchedPadIDs = switchTracker.padIDs
    }
    func openDeck(_ id: String) {
        guard snapshot.decks.contains(where: { $0.id == id }) else { error = "This deck no longer exists."; return }
        guard id != selectedDeckId else { return }
        let history = Array((deckHistory + [selectedDeckId]).suffix(32))
        selectedDeckId = id; deckHistory = history
    }
    func goBack() {
        while let id = deckHistory.popLast() {
            if snapshot.decks.contains(where: { $0.id == id }) {
                let history = deckHistory
                selectedDeckId = id; deckHistory = history; return
            }
        }
        message("You're at the first deck.")
    }
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
    private var aiKey: String?
    private let aiSuggestions: AISuggestionClient
    var hasDeviceAIKey: Bool { aiKey != nil }
    func saveAIKey(_ value: String) throws { aiKey = try AIKeyVault.save(value) }
    func removeAIKey() throws { try AIKeyVault.delete(); aiKey = nil }
    var supportsPadSuggestions: Bool { hasDeviceAIKey || snapshot.capabilities?.contains("pad-suggestions-v1") == true }
    var supportsDeckSuggestions: Bool { hasDeviceAIKey || snapshot.capabilities?.contains("deck-suggestions-v1") == true }
    var supportsSoundSuggestions: Bool { hasDeviceAIKey || snapshot.capabilities?.contains("sound-suggestions-v1") == true }
    func suggestSoundAppearances(_ request: SoundSuggestionRequest) async throws -> [String: PadSuggestion] {
        if let key = aiKey {
            let generation = epoch
            let result = try await aiSuggestions.sounds(request, snapshot: snapshot, key: key)
            try Task.checkCancellation()
            guard generation == epoch, aiKey == key else { throw CancellationError() }
            return result
        }
        guard let client, padSuggestionsEnabled, supportsSoundSuggestions else { throw RiffError.message("Set up AI suggestions in Riff, or enable them in the updated Windows companion.") }
        let generation = epoch
        let result: SoundSuggestionBatch = try await client.request("/api/sound-suggestions", method: "POST", body: JSONEncoder().encode(request))
        try Task.checkCancellation()
        guard generation == epoch, connected else { throw CancellationError() }
        return try result.appearances(for: request.clipIds)
    }
    func suggestDeck(_ request: DeckSuggestionRequest) async throws -> DeckSuggestion {
        if let key = aiKey {
            let generation = epoch
            let result = try await aiSuggestions.deck(request, snapshot: snapshot, key: key)
            try Task.checkCancellation()
            guard generation == epoch, aiKey == key else { throw CancellationError() }
            return result
        }
        guard let client, padSuggestionsEnabled, supportsDeckSuggestions else { throw RiffError.message("Set up AI suggestions in Riff, or enable them in the updated Windows companion.") }
        let generation = epoch
        let result: DeckSuggestion = try await client.request("/api/deck-suggestion", method: "POST", body: JSONEncoder().encode(request))
        try Task.checkCancellation()
        guard generation == epoch, connected else { throw CancellationError() }
        return try result.validated()
    }
    func createSuggestedDeck(_ deck: Deck, buttons: [DeckSuggestedButton], progress: (String) -> Void = { _ in }) async throws {
        if buttons.isEmpty {
            guard !snapshot.decks.contains(where: { $0.id == deck.id }) else { throw RiffError.message("This deck already exists.") }
            progress("Saving your deck…")
            try await saveDecks(snapshot.decks + [deck]); selectedDeckId = deck.id
            return
        }
        guard !busy, !connecting else { throw RiffError.message("Wait for the current change to finish.") }
        guard snapshot.decks.count < 20, !snapshot.decks.contains(where: { $0.id == deck.id }) else { throw RiffError.message("The deck list changed. Check your decks before creating another.") }
        progress("Saving your deck…")
        try await saveDecks(SuggestedDeckBuilder.decks(adding: deck, buttons: buttons, to: snapshot))
        selectedDeckId = deck.id
    }

    var padSuggestionsEnabled: Bool { hasDeviceAIKey || (connected && snapshot.capabilities?.contains("pad-suggestions-enabled-v1") == true) }
    func suggestPadAppearance(_ request: PadSuggestionRequest) async throws -> PadSuggestion {
        if let key = aiKey {
            let generation = epoch
            let result = try await aiSuggestions.pad(request, snapshot: snapshot, key: key)
            try Task.checkCancellation()
            guard generation == epoch, aiKey == key else { throw CancellationError() }
            return result
        }
        guard let client, padSuggestionsEnabled else { throw RiffError.message("Set up AI suggestions in Riff’s AI settings.") }
        let generation = epoch
        let result: PadSuggestion = try await client.request("/api/pad-suggestion", method: "POST", body: JSONEncoder().encode(request))
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
        return try result.validated()
    }
    private var players: [String: any LocalSoundPlayer] = [:]
    private var localQueue: [(pad: Pad, url: URL)] = []
    private let makeLocalSoundPlayer: @MainActor (URL) throws -> any LocalSoundPlayer
    private var previewPlayer: AVAudioPlayer?
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = UUID()
    var isPreviewPlaying: Bool { previewPlayer?.isPlaying == true }
    private var playback = SoundPlaybackTracker()
    private var playbackRefreshRunning = false
    var playingPadIDs: Set<String> = []
    var queuedPadIDs: [String] = []
    func queuePosition(for padID: String) -> Int? { queuedPadIDs.firstIndex(of: padID).map { $0 + 1 } }
    var supportsMonitoring: Bool { snapshot.capabilities?.contains("audio-monitor-v1") == true }
    var supportsQueue: Bool { snapshot.capabilities?.contains("soundboard-queue-v1") == true }
    var availablePlaybackModes: [SoundPlaybackMode] {
        SoundPlaybackMode.allCases.filter { $0 != .queue || !connected || supportsQueue }
    }
    var effectiveSoundMode: SoundPlaybackMode { connected && soundMode == .queue && !supportsQueue ? .single : soundMode }
    var soundMode = SoundPlaybackMode(rawValue: UserDefaults.standard.string(forKey: "soundMode") ?? "") ?? .overlap {
        didSet { UserDefaults.standard.set(soundMode.rawValue, forKey: "soundMode") }
    }
    var supportsPlayback: Bool { snapshot.capabilities?.contains("soundboard-playback-v1") == true }
    private func stopLocalSounds() {
        stopPreview()
        for player in players.values { player.stop() }
        players.removeAll(); playingPadIDs.removeAll(); localQueue.removeAll(); queuedPadIDs.removeAll()
    }
    private func acceptPlayback(_ next: SoundPlaybackState?) {
        guard let next else { return }
        playback.accept(next); playingPadIDs = playback.padIDs; queuedPadIDs = playback.queuedPadIDs
    }
    func refreshPlayback() async {
        if !connected {
            refreshLocalPlayback()
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
            if generation == epoch { playingPadIDs.removeAll(); queuedPadIDs.removeAll() }
        }
    }
    private var toastTask: Task<Void, Never>?
    private var refreshRunning = false
    private var epoch = 0
    private var cachedData: Data?
    private var knownBundledSoundIDs: Set<String> = []
    private var deletedClipIDs: Set<String> = []
    private var deckChanges: DeckChanges?
    private var gameCatalog = GameCatalog(games: [])
    var hasPendingDeckChanges: Bool { deckChanges != nil }
    var deckSyncIssue: String?
    private var deckSyncTask: Task<Void, Never>?
    private let snapshotCacheURL: URL
    var selectedDeck: Deck? { snapshot.decks.first { $0.id == selectedDeckId } }
    var paired: Bool { client != nil }
    var outputName: String { snapshot.outputs.first { $0.id == snapshot.outputId }?.name ?? "PC default output" }
    var cableSelected: Bool { outputName.localizedCaseInsensitiveContains("cable") || outputName.localizedCaseInsensitiveContains("voicemeeter") }

    convenience init() { self.init(cacheURL: Self.cacheURL, pairing: PairingVault.load(), aiKey: AIKeyVault.load()) }

    init(cacheURL: URL, pairing: Pairing?, aiKey: String? = nil, aiSuggestions: AISuggestionClient? = nil, makeLocalSoundPlayer: @escaping @MainActor (URL) throws -> any LocalSoundPlayer = { try DeviceSoundPlayer(url: $0) }) {
        self.aiKey = aiKey; self.aiSuggestions = aiSuggestions ?? AISuggestionClient()
        self.makeLocalSoundPlayer = makeLocalSoundPlayer
        snapshotCacheURL = cacheURL
        if let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) { snapshot = saved; cachedData = data }
        gameCatalog = snapshot.localGameCatalog ?? GameCatalog(companionID: pairing?.fingerprint, games: snapshot.games)
        snapshot.games = gameCatalog.games
        snapshot.localGameCatalog = nil
        knownBundledSoundIDs = snapshot.localKnownBundledSoundIDs ?? []
        deletedClipIDs = snapshot.localDeletedClipIDs ?? []
        let bundled = SoundPacks.clips
        let existing = Set(snapshot.clips.map(\.id))
        snapshot.clips += bundled.filter { !existing.contains($0.id) && !knownBundledSoundIDs.contains($0.id) && !deletedClipIDs.contains($0.id) }
        knownBundledSoundIDs.formUnion(bundled.map(\.id))
        snapshot.clips.removeAll { deletedClipIDs.contains($0.id) }
        SoundPacks.refreshDurations(&snapshot.clips)
        deckChanges = snapshot.localDeckChanges
        snapshot.localDeckChanges = nil
        if let deckChanges { snapshot.decks = deckChanges.decks }
        if selectedDeck == nil { selectedDeckId = snapshot.decks.first?.id ?? "" }
        if let pairing { client = CompanionClient(pairing: pairing) }
        do { try persist(snapshot, changes: deckChanges) }
        catch { self.error = "Could not save the sound library: \(error.localizedDescription)" }
    }
    static var cacheURL: URL { URL.applicationSupportDirectory.appendingPathComponent("snapshot.json") }
    func message(_ text: String) {
        toastTask?.cancel(); toast = text
        toastTask = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { toast = nil } }
    }
    func pair(_ link: String) async throws {
        guard !busy, !connecting else { return }
        connecting = true; epoch += 1
        let generation = epoch
        defer { connecting = false; scheduleDeckSync() }
        let pairing = try Pairing.parse(link)
        let next = CompanionClient(pairing: pairing)
        let state: Snapshot = try await next.request("/api/state")
        guard generation == epoch else { throw CancellationError() }
        try PairingVault.save(pairing)
        stopLocalSounds(); playback = SoundPlaybackTracker()
        smartProfiles = SmartProfiles(); switchTracker = SoundPlaybackTracker(); switchedPadIDs.removeAll(); client = next; connected = true; connectionIssue = nil
        apply(state)
        message("Connected to \(state.computerName)")
    }
    func disconnect() {
        smartProfiles = SmartProfiles(); switchTracker = SoundPlaybackTracker(); switchedPadIDs.removeAll(); deckHistory.removeAll()
        epoch += 1; client = nil; connected = false; connectionIssue = nil; PairingVault.delete(); stopLocalSounds(); playback = SoundPlaybackTracker()
    }
    func refresh() async {
        if let deckSyncTask { await deckSyncTask.value; return }
        guard let client, !busy, !connecting, !refreshRunning else { return }
        refreshRunning = true; let generation = epoch
        defer { refreshRunning = false }
        do {
            let state: Snapshot = try await client.request("/api/state")
            guard generation == epoch, !busy else { return }
            if !connected { stopLocalSounds() }
            connected = true; connectionIssue = nil; apply(state)
            if hasPendingDeckChanges || !deletedClipIDs.isEmpty {
                scheduleDeckSync(state: state)
                await deckSyncTask?.value
            }
        } catch {
            if generation == epoch {
                connected = false; playingPadIDs.removeAll(); queuedPadIDs.removeAll()
                connectionIssue = error is RiffError ? error.localizedDescription : "Make sure Riff is open on your PC and both devices are on the same network."
            }
        }
    }
    private func apply(_ incoming: Snapshot) {
        var state = incoming
        gameCatalog = gameCatalog.updating(with: incoming.games, companionID: client?.pairing.fingerprint)
        state.games = gameCatalog.games
        state.localGameCatalog = nil
        state.localDeckChanges = nil
        state.localKnownBundledSoundIDs = nil; state.localDeletedClipIDs = nil
        state.clips.removeAll { deletedClipIDs.contains($0.id) }
        SoundPacks.refreshDurations(&state.clips)
        if let changes = deckChanges {
            state.decks = changes.merged(with: incoming.decks)
            deckChanges = DeckChanges(base: incoming.decks, decks: state.decks)
        }
        snapshot = state
        if !state.decks.contains(where: { $0.id == selectedDeckId }) { selectedDeckId = state.decks.first?.id ?? "" }
        acceptSwitchState(state.switchState)
        if let id = smartProfiles.selection(in: state, followApps: followApps && supportsSmartProfiles,
                                           followGames: autoSwitch, paused: editing || interacting),
           let deck = state.decks.first(where: { $0.id == id }), id != selectedDeckId {
            selectedDeckId = id; message("Switched to \(deck.name)")
        }
        do { try persist(state, changes: deckChanges) }
        catch { deckSyncIssue = "Could not save decks on this iPad: \(error.localizedDescription)" }
    }
    private func persist(_ state: Snapshot, changes: DeckChanges?) throws {
        var saved = state; saved.localDeckChanges = changes
        saved.localGameCatalog = gameCatalog
        saved.localKnownBundledSoundIDs = knownBundledSoundIDs; saved.localDeletedClipIDs = deletedClipIDs
        try FileManager.default.createDirectory(at: snapshotCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(saved)
        if data != cachedData { try data.write(to: snapshotCacheURL, options: .atomic); cachedData = data }
    }

    private func scheduleDeckSync(state: Snapshot? = nil) {
        guard deckSyncTask == nil, (hasPendingDeckChanges || !deletedClipIDs.isEmpty), connected, !busy, !connecting, let client else { return }
        let generation = epoch
        deckSyncTask = Task {
            await syncDeckChanges(using: client, state: state, generation: generation)
            await syncDeletedClips(using: client, generation: generation)
            deckSyncTask = nil
            // An edit made during the upload is already on disk. Send it next.
            if generation != epoch { scheduleDeckSync() }
        }
    }

    /// Background uploads never block editing. The epoch rejects responses predating a newer edit.
    private func syncDeckChanges(using client: CompanionClient, state initial: Snapshot? = nil, generation: Int) async {
        guard hasPendingDeckChanges else { return }
        do {
            var remote: Snapshot
            if let initial { remote = initial }
            else { remote = try await client.request("/api/state") }
            for attempt in 0..<3 {
                guard generation == epoch, connected, let changes = deckChanges else { return }
                let decks = changes.merged(with: remote.decks)
                try DeckChanges.validate(decks, in: remote)
                // Older companions may silently ignore fields they do not understand.
                for deck in decks {
                    let package = try DeckPackage.make(deck: deck, snapshot: remote, grid: GridPreferences())
                    if let issue = package.compatibilityIssue(in: remote) { throw RiffError.message(issue) }
                    if !(deck.linkedAppId ?? "").isEmpty, remote.capabilities?.contains("smart-profiles-v1") != true {
                        throw RiffError.message("Update the Windows companion to sync linked applications.")
                    }
                }
                do {
                    let saved: Snapshot
                    if DeckChanges.same(decks, remote.decks) { saved = remote }
                    else {
                        struct Update: Encodable { let version: Int; let decks: [Deck] }
                        saved = try await client.request("/api/decks", method: "PUT", body: JSONEncoder().encode(Update(version: remote.version, decks: decks)))
                    }
                    guard generation == epoch, connected else { return }
                    // Clear the pending edits only after the acknowledgement is durable.
                    try persist(saved, changes: nil)
                    deckChanges = nil; deckSyncIssue = nil; apply(saved)
                    return
                } catch RiffError.http(409, _) where attempt < 2 {
                    remote = try await client.request("/api/state")
                }
            }
        } catch {
            guard generation == epoch else { return }
            deckSyncIssue = error.localizedDescription
            if error is URLError { connected = false; connectionIssue = "Make sure Riff is open on your PC and both devices are on the same network." }
        }
    }
    func trigger(_ source: Pad, gesture: PadGesture = .tap) async {
        guard let pad = source.resolved(for: gesture) else { error = "No action is assigned to this gesture."; return }
        if gesture != .tap, connected, !supportsKeyLogic { error = "Update the Windows companion to use double-tap and hold actions."; return }
        if connected, snapshot.blocksDesktopAction(pad) { error = "Turn off Soundboard mode in the Windows companion to use this desktop action."; return }
        if pad.kind == "deck" { openDeck(pad.value); return }
        if pad.kind == "back" { goBack(); return }
        if pad.kind == "stop" { await stopAll(); return }
        if connected, ActionKind(rawValue: pad.kind)?.needsDeckActions == true, !supportsDeckActions {
            error = "Update the Windows companion to use this action."; return
        }
        if !connected {
            guard pad.kind == "sound", let url = SoundPacks.audioURL(forClipID: pad.value) ?? Bundle.main.url(forResource: pad.value, withExtension: "wav") else {
                error = "Connect your PC to use this action."; return
            }
            do {
#if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
#endif
                if soundMode != .queue { localQueue.removeAll(); queuedPadIDs.removeAll() }
                refreshLocalPlayback()
                if let index = localQueue.firstIndex(where: { $0.pad.id == pad.id }) {
                    localQueue.remove(at: index); queuedPadIDs = localQueue.map { $0.pad.id }
                    message("Removed \(pad.title) from queue"); return
                }
                if let playing = players.removeValue(forKey: pad.id) {
                    playing.stop(); refreshLocalPlayback()
                    message("Stopped \(pad.title)"); return
                }
                if soundMode == .single { stopLocalSounds() }
                if soundMode == .queue && !players.isEmpty {
                    guard localQueue.count < 48 else { throw RiffError.message("48 sounds are already queued. Remove a sound or wait for one to finish.") }
                    localQueue.append((pad, url)); queuedPadIDs = localQueue.map { $0.pad.id }
                    message("Queued: \(pad.title)"); return
                }
                guard players.count < 16 else { throw RiffError.message("16 sounds are already playing. Stop a sound before starting another.") }
                try playLocalSound(pad, url: url)
                message("Playing on iPad: \(pad.title)")
            } catch { self.error = error.localizedDescription }
            return
        }
        if hasPendingDeckChanges {
            scheduleDeckSync()
            await deckSyncTask?.value
            if let changes = deckChanges {
                let pcPad = changes.base.flatMap(\.pads).first { $0.id == pad.id }
                guard let pcPad, DeckChanges.same(pcPad, source) else {
                    error = "This button isn't ready on your PC yet. Try again in a moment."; return
                }
            }
        }
        guard let client, connected else { return }
        let generation = epoch
        activePad = pad.id
        defer { if activePad == pad.id { activePad = nil } }
        do {
            struct Trigger: Encodable { let padId: String; let requestId: String; let toggle: Bool?; let soundMode: String?; let gesture: String? }
            let result: Acknowledgement = try await client.request("/api/trigger", method: "POST", body: JSONEncoder().encode(Trigger(padId: pad.id, requestId: UUID().uuidString, toggle: supportsPlayback ? true : nil, soundMode: supportsPlayback ? effectiveSoundMode.rawValue : nil, gesture: gesture == .tap ? nil : gesture.rawValue)))
            guard generation == epoch, connected else { return }
            acceptPlayback(result.playback)
            acceptSwitchState(result.switchState)
            if pad.kind != "sound" || !supportsPlayback { message("\(pad.title) sent to PC") }
        } catch { self.error = "\(error.localizedDescription) The action was not retried, to avoid playing it twice." }
    }
    private func playLocalSound(_ pad: Pad, url: URL) throws {
        let player = try makeLocalSoundPlayer(url)
        player.onCompletion = { [weak self] in self?.refreshLocalPlayback() }
        player.volume = snapshot.volume
        guard player.play() else { throw RiffError.message("This sound could not be played.") }
        players[pad.id] = player; playingPadIDs = Set(players.keys)
    }
    private func refreshLocalPlayback() {
        guard !connected else { return }
        players = players.filter { $0.value.isPlaying }
        playingPadIDs = Set(players.keys)
        while players.isEmpty && !localQueue.isEmpty {
            let next = localQueue.removeFirst()
            queuedPadIDs = localQueue.map { $0.pad.id }
            do { try playLocalSound(next.pad, url: next.url) }
            catch { self.error = "Could not play queued sound \(next.pad.title): \(error.localizedDescription)" }
        }
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
        guard !busy, !connecting else { throw RiffError.message("Wait for the current change to finish.") }
        try DeckChanges.validate(decks, in: snapshot)
        var local = snapshot; local.decks = decks
        let changes = DeckChanges(base: deckChanges?.base ?? snapshot.decks, decks: decks)
        // A save is successful only after the edits and their merge base reach disk together.
        try persist(local, changes: changes)
        deckChanges = changes; snapshot = local; deckSyncIssue = nil
        if selectedDeck == nil { selectedDeckId = decks.first?.id ?? "" }
        epoch += 1
        scheduleDeckSync()
    }
    func savePad(_ pad: Pad, in deckId: String) async throws {
        try await saveDecks(snapshot.decksSaving(pad, in: deckId))
        selectedDeckId = deckId
        message("Saved \(pad.title)")
    }
    func setPinned(_ pinned: Bool, pad: Pad) async {
        guard supportsPinnedPads else { error = "Update the Windows companion to pin buttons."; return }
        guard let deck = snapshot.decks.first(where: { $0.pads.contains(where: { $0.id == pad.id }) }),
              var current = deck.pads.first(where: { $0.id == pad.id }) else { return }
        current.pinned = pinned ? true : nil
        do { try await savePad(current, in: deck.id) }
        catch { self.error = error.localizedDescription }
    }
    func movePad(_ id: String, to target: String) async {
        var decks = snapshot.decks
        guard let d = decks.firstIndex(where: { $0.id == selectedDeckId }),
              let from = decks[d].pads.firstIndex(where: { $0.id == id }),
              let to = decks[d].pads.firstIndex(where: { $0.id == target }), from != to else { return }
        guard decks[d].pads[from].isPinned == decks[d].pads[to].isPinned else {
            message("Pinned buttons stay at the start of each page."); return
        }
        let pad = decks[d].pads.remove(at: from); decks[d].pads.insert(pad, at: to)
        do { try await saveDecks(decks) } catch { self.error = error.localizedDescription }
    }
    func audio(output: String, volume: Float, monitorEnabled: Bool? = nil, monitorOutput: String? = nil, monitorVolume: Float? = nil) async throws {
        guard let client, connected else { throw RiffError.message("Connect your PC to change audio routing.") }
        guard !busy else { throw RiffError.message("Wait for the current change to finish.") }
        busy = true; epoch += 1; defer { busy = false }
        struct Settings: Encodable {
            let outputId: String
            let volume: Float
            var monitorEnabled: Bool? = nil
            var monitorOutputId: String? = nil
            var monitorVolume: Float? = nil
        }
        var settings = Settings(outputId: output, volume: volume)
        if supportsMonitoring {
            settings.monitorEnabled = monitorEnabled
            settings.monitorOutputId = monitorOutput
            settings.monitorVolume = monitorVolume
        }
        let state: Snapshot = try await client.request("/api/audio", method: "PUT", body: JSONEncoder().encode(settings))
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
    private func soundIsUsed(_ id: String, in decks: [Deck]) -> Bool {
        decks.flatMap(\.pads).contains { pad in
            pad.actionReferences.contains { $0.kind == "sound" && $0.value == id }
        }
    }
    func deleteClip(_ clip: Clip) async {
        guard !busy else { error = "Wait for the current change to finish."; return }
        guard !soundIsUsed(clip.id, in: snapshot.decks) else { error = "Remove buttons using this sound before deleting it."; return }
        epoch += 1
        let previous = snapshot
        deletedClipIDs.insert(clip.id)
        snapshot.clips.removeAll { $0.id == clip.id }
        do { try persist(snapshot, changes: deckChanges) }
        catch {
            snapshot = previous; deletedClipIDs.remove(clip.id)
            self.error = error.localizedDescription; return
        }
        stopPreview(); favoriteClipIDs.remove(clip.id)
        message("Sound deleted")
        scheduleDeckSync()
    }
    private func syncDeletedClips(using client: CompanionClient, generation: Int) async {
        guard generation == epoch, connected, !deletedClipIDs.isEmpty, !hasPendingDeckChanges else { return }
        do {
            var remote: Snapshot = try await client.request("/api/state")
            for id in deletedClipIDs.sorted() {
                guard generation == epoch, connected else { return }
                if soundIsUsed(id, in: remote.decks) {
                    deletedClipIDs.remove(id); apply(remote)
                    error = "A PC button uses this sound. Remove that button before deleting the sound."
                    continue
                }
                if remote.clips.contains(where: { $0.id == id }) {
                    remote = try await client.request("/api/clips/\(id)", method: "DELETE")
                }
                guard generation == epoch, connected else { return }
                deletedClipIDs.remove(id); apply(remote)
            }
        } catch {
            guard generation == epoch else { return }
            if error is URLError { connected = false }
        }
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
    func audioData(for clip: Clip) async throws -> Data {
        if let url = SoundPacks.audioURL(forClipID: clip.id) ?? Bundle.main.url(forResource: clip.id, withExtension: "wav") {
            return try Data(contentsOf: url)
        }
        guard let client, connected else {
            throw RiffError.message("Connect your PC to preview or edit this sound on your iPad.")
        }
        guard snapshot.capabilities?.contains("clip-audio-v1") == true else {
            throw RiffError.message("Update Riff on your PC to preview or edit imported and recorded sounds on this iPad.")
        }
        let id = clip.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return try await client.requestData("/api/clips/\(id)/audio")
    }
    func preview(_ clip: Clip) async {
        stopPreview()
        let generation = previewGeneration
        let task = Task {
            defer { if generation == previewGeneration { previewTask = nil } }
            do {
                let data = try await audioData(for: clip)
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
                let result: Acknowledgement = try await client.request("/api/preview", method: "POST", body: JSONEncoder().encode(Preview(clipId: clip.id, soundMode: supportsPlayback ? effectiveSoundMode.rawValue : nil)))
                guard generation == epoch, connected else { return }
                acceptPlayback(result.playback)
                message("Playing on PC: \(clip.name)")
            } catch { self.error = error.localizedDescription }
        } else { error = "Connect your PC to test its audio output." }
    }
}
struct Acknowledgement: Decodable { let ok: Bool; let playback: SoundPlaybackState?; var switchState: SoundPlaybackState? = nil }
