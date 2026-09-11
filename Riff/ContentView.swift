import SwiftUI

@main struct RiffApp: App {
    @State private var store = RiffStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(store).tint(Palette.accent)
#if DEBUG
                .preferredColorScheme(DesignPreview.colorScheme ?? ThemePreferences.shared.appearance.colorScheme)
#else
                .preferredColorScheme(ThemePreferences.shared.appearance.colorScheme)
#endif
        }
    }
}

struct ContentView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var destination: Destination?
    @State private var editor: Pad?
    @State private var editDeck: Deck?
    @State private var pageMemory = DeckPageMemory()
    @State private var picker = false
    @State private var pendingClip: Clip?
    @State private var playMode = false
    enum Destination: String, Identifiable {
        case connection, recording, settings, sounds, grid, audio, updates, audioSetup, musicSetup
        var id: String { rawValue }
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let layout = BoardLayout(size: geometry.size, preferences: store.grid, playMode: playMode)
                VStack(spacing: 0) {
                    if !playMode {
                        deckHeading
                            .padding(.horizontal, layout.margin)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                        if store.connected, let release = store.updates.release,
                           release.isNewer(than: store.snapshot.companionVersion) || store.snapshot.companionVersion.flatMap(ReleaseVersion.init) == nil {
                            Button { destination = .updates } label: {
                                Label(release.isNewer(than: store.snapshot.companionVersion) ? "Update Windows companion · \(release.tag_name)" : "Check your Windows companion version", systemImage: "arrow.down.circle")
                                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.horizontal, layout.margin).padding(.bottom, 8)
                        }
                        if store.editing {
                            HStack {
                                Text("Drag to move. Tap to edit.").foregroundStyle(.secondary)
                                Spacer()
                                Button("Deck settings") { editDeck = store.selectedDeck }
                            }
                            .font(.subheadline).padding(.horizontal, layout.margin).padding(.bottom, 8)
                        }
                    }
                    board(layout: layout)
                    if playMode {
                        playBar.padding(.horizontal, layout.margin).padding(.bottom, 12)
                    } else {
                        playerBar.padding(.horizontal, layout.margin).padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Palette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if playMode {
                        Button { picker = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: store.selectedDeck?.icon ?? "square.grid.2x2")
                                Text(store.selectedDeck?.name ?? "Your deck").lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                            }.font(.headline)
                        }
                        .accessibilityLabel("Choose deck, \(store.selectedDeck?.name ?? "")")
                        .popover(isPresented: $picker, arrowEdge: .top) {
                            deckPicker.presentationCompactAdaptation(.sheet)
                        }
                    } else {
                        Button { destination = .connection } label: {
                            HStack(spacing: 7) {
                                Image(systemName: store.connected ? "desktopcomputer" : "link")
                                Text(store.connected ? store.snapshot.computerName : "Connect PC").lineLimit(1)
                            }.font(.subheadline.weight(.medium))
                        }.accessibilityIdentifier("connection")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if playMode {
                        Button("Done", systemImage: "arrow.down.right.and.arrow.up.left") {
                            withAnimation(reduceMotion ? nil : .snappy) { playMode = false }
                        }.accessibilityLabel("Exit Play mode")
                    } else {
                        if store.editing {
                            Button("Done") { withAnimation(.snappy) { store.editing = false } }.fontWeight(.semibold)
                        } else {
                            Button { destination = .sounds } label: { Image(systemName: "waveform.path") }.accessibilityLabel("Sounds")
                            Button("Play mode", systemImage: "play.rectangle") { enterPlayMode() }
                                .labelStyle(.iconOnly).accessibilityIdentifier("play-mode")
                            Menu {
                                Button("Edit buttons", systemImage: "square.grid.2x2") { store.editing = true }.disabled(!store.connected)
                                Button("Grid size", systemImage: "square.grid.3x3") { destination = .grid }
                                Button("Sound controls", systemImage: "speaker.wave.2") { destination = .audio }
                                Button("Deck settings", systemImage: "pencil") { editDeck = store.selectedDeck }.disabled(!store.connected)
                                Divider()
                                Button("Settings", systemImage: "gearshape") { destination = .settings }
                            } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Deck options")
                        }
                        Button {
                            if store.connected { editor = Pad() } else { destination = .connection }
                        } label: { Image(systemName: "plus") }.accessibilityLabel("Add button")
                    }
                }
            }
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(item: $destination, onDismiss: {
            if let clip = pendingClip { pendingClip = nil; editor = Pad(title: clip.buttonTitle, icon: "waveform", value: clip.id) }
        }) { choice in
            switch choice {
            case .connection: ConnectionView()
            case .recording: RecordingView { clip in pendingClip = clip; destination = nil }
            case .settings: SettingsView()
            case .updates: NavigationStack {
                CompanionUpdatesView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { destination = nil } } }
            }
            case .audio: AudioControlsView()
            case .audioSetup: NavigationStack {
                AudioSetupView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { destination = nil } } }
            }
            case .musicSetup: NavigationStack {
                MusicSetupView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { destination = nil } } }
            }
            case .grid: NavigationStack { GridLayoutView() }
            case .sounds:
                NavigationStack {
                    LibraryView(onAssign: { clip in pendingClip = clip; destination = nil }, onAdded: { destination = nil })
                        .navigationTitle("Sounds")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { destination = nil } } }
                }
            }
        }
        .sheet(item: $editor) { pad in PadEditor(pad: pad, deckId: store.selectedDeckId) }
        .sheet(item: $editDeck) { deck in DeckEditor(deck: deck) }
        .alert("Something needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onChange(of: editor != nil || editDeck != nil || destination != nil || picker) { _, presented in store.interacting = presented }
#if DEBUG
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            DesignPreview.orient()
            switch DesignPreview.screen {
            case "play": enterPlayMode()
            case "pages", "play-pages":
                DesignPreview.configurePages(store)
                if DesignPreview.screen == "play-pages" { enterPlayMode() }
            case "grid": destination = .grid
            case "audio": destination = .audio
            case "playback-check": await DesignPreview.checkPlayback(store)
            case "sounds", "rename", "import", "sound-selection", "add-sounds": destination = .sounds
            case "recording", "recording-trim": destination = .recording
            case "settings", "appearance": destination = .settings
            case "audio-setup": destination = .audioSetup
            case "music-setup": destination = .musicSetup
            case "updates", "changelog", "markdown": destination = .updates
            case "connection": destination = .connection
            case "editor": editor = store.selectedDeck?.pads.first
            case "decks": picker = true
            default: break
            }
        }
#endif
        .task(id: store.paired && scenePhase == .active) {
            guard store.paired, scenePhase == .active else { return }
            while !Task.isCancelled { await store.updates.check(); try? await Task.sleep(for: .seconds(60)) }
        }
        .task(id: scenePhase) {
            UIApplication.shared.isIdleTimerDisabled = scenePhase == .active
            guard scenePhase == .active else { return }
            while !Task.isCancelled { await store.refresh(); try? await Task.sleep(for: .seconds(3)) }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled { await store.refreshPlayback(); try? await Task.sleep(for: .milliseconds(250)) }
        }
    }
    private var deckHeading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Button { picker = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(store.selectedDeck?.name ?? "Your deck")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-0.8)
                            .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.65)
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.title3).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain).accessibilityLabel("Choose deck, \(store.selectedDeck?.name ?? "")")
                    .popover(isPresented: $picker, arrowEdge: .top) {
                        deckPicker.presentationCompactAdaptation(.sheet)
                    }
                if let toast = store.toast {
                    Text(toast).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        .accessibilityAddTraits(.updatesFrequently)
                } else if !store.connected {
                    Text("Sounds play on this iPad until you connect.").font(.subheadline).foregroundStyle(.secondary)
                } else if !store.snapshot.activeGameName.isEmpty {
                    Label(store.snapshot.activeGameName, systemImage: "gamecontroller").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("\(store.selectedDeck?.pads.count ?? 0) buttons").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
    private var deckPicker: some View {
        NavigationStack {
            List {
                ForEach(store.snapshot.decks) { deck in
                    Button {
                        store.selectedDeckId = deck.id; picker = false
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: deck.icon).font(.title3).foregroundStyle(Palette.accent).frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(deck.name).fontWeight(.medium).foregroundStyle(.primary)
                                Text("\(deck.pads.count) buttons").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.selectedDeckId == deck.id { Image(systemName: "checkmark").fontWeight(.semibold) }
                        }.padding(.vertical, 7)
                    }
                }
                if !playMode {
                    Section {
                    Button("New deck", systemImage: "plus") {
                        picker = false
                        if store.connected { editDeck = Deck() } else { destination = .connection }
                    }
                    }
                }
            }.navigationTitle("Your decks").navigationBarTitleDisplayMode(.inline)
        }.frame(minWidth: 320, idealWidth: 360, minHeight: 300, idealHeight: 420)
    }
    private func board(layout: BoardLayout) -> some View {
        let pads = store.selectedDeck?.pads ?? []
        let pages = max(1, (pads.count + layout.capacity - 1) / layout.capacity)
        let page = pageMemory.page(deckID: store.selectedDeckId, capacity: layout.capacity, padCount: pads.count)
        let selection = Binding(get: {
            pageMemory.page(deckID: store.selectedDeckId, capacity: layout.capacity, padCount: pads.count)
        }, set: { value in
            pageMemory.select(value, deckID: store.selectedDeckId, capacity: layout.capacity, padCount: pads.count)
        })
        return VStack(spacing: 0) {
            if pads.isEmpty {
                ContentUnavailableView {
                    Label("Add your first button", systemImage: "square.grid.2x2")
                } description: { Text("Choose a sound, a shortcut, or something you do every day.") } actions: {
                    if playMode {
                        Button("Choose another deck") { picker = true }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Add button", systemImage: "plus") { editor = Pad() }.buttonStyle(.borderedProminent).disabled(!store.connected)
                    }
                }
            } else {
                TabView(selection: selection) {
                    ForEach(0..<pages, id: \.self) { number in
                        let start = number * layout.capacity
                        let end = min(start + layout.capacity, pads.count)
                        let shown = Array(pads[start..<end])
                        GeometryReader { viewport in
                            ScrollView([.horizontal, .vertical]) {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: layout.gap), count: layout.columns), spacing: layout.gap) {
                                    ForEach(shown) { pad in
                                        tile(pad, pads: pads).frame(height: layout.padHeight)
                                    }
                                }
                                .frame(width: layout.gridWidth)
                                .frame(minHeight: max(0, viewport.size.height - 24))
                                .padding(.horizontal, layout.margin)
                                .padding(.vertical, 12)
                            }
                            .defaultScrollAnchor(.topLeading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .tag(number)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
            }
            if pages > 1 {
                HStack(spacing: 20) {
                    Button { withAnimation { selection.wrappedValue = page - 1 } } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(page == 0).accessibilityLabel("Previous page")
                    Menu {
                        Picker("Page", selection: selection) {
                            ForEach(0..<pages, id: \.self) { number in
                                Text("\(number + 1) · \(pads[number * layout.capacity].title)").tag(number)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(page + 1) of \(pages)").monospacedDigit()
                            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                        }.font(.subheadline).frame(minWidth: 88, minHeight: 44)
                    }.accessibilityLabel("Page \(page + 1) of \(pages)")
                        .accessibilityHint("Choose a page, or swipe across the buttons")
                    Button { withAnimation { selection.wrappedValue = page + 1 } } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(page == pages - 1).accessibilityLabel("Next page")
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    @ViewBuilder private func tile(_ pad: Pad, pads: [Pad]) -> some View {
        let blocked = store.connected && store.snapshot.blocksDesktopAction(pad)
        if playMode {
            PadTile(pad: pad, active: store.activePad == pad.id, playing: store.playingPadIDs.contains(pad.id), blocked: blocked) {
                trigger(pad)
            }
        } else {
            PadTile(pad: pad, editing: store.editing, active: store.activePad == pad.id, playing: store.playingPadIDs.contains(pad.id), blocked: blocked && !store.editing) {
                if store.editing { editor = pad } else { trigger(pad) }
            }
            .modifier(PadReordering(enabled: store.editing, id: pad.id) { id in Task { await store.movePad(id, to: pad.id) } })
            .contextMenu {
                Button("Edit button", systemImage: "pencil") { editor = pad }.disabled(!store.connected)
                Button("Duplicate button", systemImage: "plus.square.on.square") { editor = pad.duplicated() }
                    .disabled(!store.connected || pads.count >= 48)
                Button("Rearrange buttons", systemImage: "hand.draw") { store.editing = true }.disabled(!store.connected)
                if let index = pads.firstIndex(where: { $0.id == pad.id }) {
                    if index > 0 {
                        Button("Move earlier", systemImage: "arrow.left") { Task { await store.movePad(pad.id, to: pads[index - 1].id) } }.disabled(!store.connected)
                    }
                    if index + 1 < pads.count {
                        Button("Move later", systemImage: "arrow.right") { Task { await store.movePad(pad.id, to: pads[index + 1].id) } }.disabled(!store.connected)
                    }
                }
            }
        }
    }
    private func enterPlayMode() {
        withAnimation(reduceMotion ? nil : .snappy) { store.editing = false; playMode = true }
    }
    private func trigger(_ pad: Pad) {
        if store.connected && store.snapshot.blocksDesktopAction(pad) {
            store.error = "Your PC is in Soundboard mode. Sounds still work. To use desktop actions, turn off Soundboard mode in the Windows companion’s Controls tab. Check your game’s rules before using keyboard shortcuts or sequences."
        } else {
            Task { await store.trigger(pad) }
        }
    }
    private var playBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Button { destination = store.paired && !store.connected ? .connection : .audio } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(store.paired && !store.connected ? "PC disconnected" : store.connected ? store.outputName : "iPad speakers",
                              systemImage: store.paired && !store.connected ? "wifi.slash" : store.cableSelected ? "mic" : "speaker.wave.2")
                            .font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                        Text(store.connected && !store.supportsPlayback ? "Sound controls" : store.soundMode.label)
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint("Open sound controls and game chat setup")
                stopButton
            }
            Text(store.toast ?? (store.connected ? [store.snapshot.soundboardOnly == true ? "Soundboard only" : "", store.snapshot.activeGameName].filter { !$0.isEmpty }.joined(separator: " · ") : "Sounds play on this iPad"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        }.padding(.top, 8)
    }
    private var playerBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                recordingButton
                Spacer(minLength: 10)
                outputButton
                Spacer(minLength: 10)
                stopButton
            }
            HStack { recordingButton; Spacer(); stopButton }
        }
        .padding(.vertical, 12)
    }
    private var recordingButton: some View {
        Button {
            destination = store.connected ? .recording : .connection
        } label: {
            Label("Record", systemImage: "record.circle").font(.body.weight(.semibold)).padding(.horizontal, 20).padding(.vertical, 15)
        }
        .foregroundStyle(Palette.accentInk).background(Palette.accent, in: Capsule()).buttonStyle(PadPressStyle())
    }
    private var outputButton: some View {
        Button { destination = .audio } label: {
            Label(store.connected ? store.outputName : "iPad speakers", systemImage: store.cableSelected ? "mic" : "speaker.wave.2")
                .font(.subheadline).lineLimit(1).truncationMode(.middle).frame(maxWidth: 270)
        }.foregroundStyle(.secondary).buttonStyle(.plain)
    }
    private var stopButton: some View {
        Button { Task { await store.stopAll() } } label: {
            Label("Stop all", systemImage: "stop.fill").font(.body.weight(.medium)).padding(.horizontal, 20).padding(.vertical, 15)
        }.foregroundStyle(.primary).background(Palette.panel, in: Capsule()).buttonStyle(PadPressStyle())
    }
}

struct PadReordering: ViewModifier {
    let enabled: Bool
    let id: String
    let move: (String) -> Void
    func body(content: Content) -> some View {
        if enabled {
            content.draggable(id).dropDestination(for: String.self) { ids, _ in
                guard let source = ids.first, source != id else { return false }
                move(source); return true
            }
        } else { content }
    }
}

struct PadTile: View {
    let pad: Pad
    var editing = false
    var active = false
    var playing = false
    var blocked = false
    var action: () -> Void = {}
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 160
            let symbolSize = min(76, max(34, geometry.size.height * 0.29))
            Button(action: action) {
                VStack(spacing: compact ? 10 : 22) {
                    Spacer(minLength: 0)
                    PadGlyph(icon: pad.icon, size: symbolSize)
                        .frame(height: symbolSize * 1.15)
                        .symbolEffect(.bounce, value: active)
                    Text(pad.title)
                        .font(.system(compact ? .body : .title3, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Palette.ink)
                .background(pad.tint, in: RoundedRectangle(cornerRadius: compact ? 24 : 34, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if editing {
                        Image(systemName: "pencil").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.6)).padding(18)
                    } else if blocked {
                        Image(systemName: "lock.fill").font(.subheadline).foregroundStyle(Palette.ink).padding(18)
                    } else if active {
                        ProgressView().tint(Palette.ink).padding(18)
                    } else if playing {
                        Image(systemName: "stop.fill").font(.caption.weight(.bold))
                            .foregroundStyle(Palette.ink).padding(10)
                            .background(.white.opacity(0.45), in: Circle()).padding(12)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: compact ? 24 : 34).strokeBorder(playing ? Palette.ink.opacity(0.6) : .white.opacity(0.3), lineWidth: playing ? 3 : 1))
                .shadow(color: pad.tint.opacity(0.12), radius: 6, y: 4)
            }.buttonStyle(PadPressStyle())
                .sensoryFeedback(.impact(weight: .light), trigger: active)
                .accessibilityLabel("\(pad.title), \(pad.typeName)")
                .accessibilityValue(blocked ? "Desktop actions disabled on PC" : playing ? "Playing" : "")
                .accessibilityHint(editing ? "Customize this button" : blocked ? "Learn about soundboard-only mode" : playing ? "Tap again to stop this sound" : "Run this action")
        }
    }
}
struct PadPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.medium)).foregroundStyle(.primary)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Palette.raised.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }
}
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).foregroundStyle(Palette.accentInk)
            .padding(.horizontal, 22).padding(.vertical, 15)
            .background(Palette.accent, in: Capsule()).opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
    }
}
#Preview { ContentView().environment(RiffStore()).tint(Palette.accent) }
