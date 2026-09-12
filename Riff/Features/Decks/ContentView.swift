import SwiftUI

struct ContentView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var destination: Destination?
    @State private var editor: Pad?
    @State private var suggestNewAppearance = true
    @State private var editDeck: Deck?
    @State private var sharingButton: Pad?
    @State private var pageMemory = DeckPageMemory()
    @State private var picker = false
    @State private var pendingClip: Clip?
    @State private var playMode = false
    @State private var selectionFeedback = 0
    @State private var stopFeedback = 0
    enum Destination: String, Identifiable {
        case sharing, connection, recording, settings, sounds, addSounds, grid, audio, updates, audioSetup, musicSetup
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
                    if store.canGoBack {
                        Button("Back", systemImage: "arrow.uturn.backward") { store.goBack() }
                    }
                    if playMode {
                        Button("Done", systemImage: "arrow.down.right.and.arrow.up.left") {
                            selectionFeedback += 1
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
                                Button("Edit buttons", systemImage: "square.grid.2x2") { store.editing = true }.disabled(store.busy)
                                Button("Grid size", systemImage: "square.grid.3x3") { destination = .grid }
                                Button("Sound controls", systemImage: "speaker.wave.2") { destination = .audio }
                                Button("Deck settings", systemImage: "pencil") { editDeck = store.selectedDeck }.disabled(store.busy)
                                Divider()
                                Button("Share & import layouts", systemImage: "square.and.arrow.up") { sharingButton = nil; destination = .sharing }
                                Button("Settings", systemImage: "gearshape") { destination = .settings }
                            } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Deck options")
                        }
                        Menu {
                            Button("Add sounds from library", systemImage: "waveform.badge.plus") { destination = .addSounds }
                            Button("Create custom button", systemImage: "slider.horizontal.3") {
                                editor = Pad()
                            }
                        } label: { Image(systemName: "plus") }.accessibilityLabel("Add to deck")
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
            case .sharing:
                if let deck = store.selectedDeck {
                    if #available(iOS 18.0, *) { LayoutSharingView(sourceDeck: deck, button: sharingButton).presentationSizing(.page) }
                    else { LayoutSharingView(sourceDeck: deck, button: sharingButton) }
                }
            case .connection: ConnectionView()
            case .recording: RecordingView { clip in pendingClip = clip; destination = nil }
            case .settings: SettingsView()
            case .updates: NavigationStack {
                CompanionUpdatesView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { destination = nil } } }
            }
            case .audio:
                if #available(iOS 18.0, *) { AudioControlsView().presentationSizing(.page) }
                else { AudioControlsView() }
            case .audioSetup: NavigationStack {
                AudioSetupView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { destination = nil } } }
            }
            case .musicSetup: NavigationStack {
                MusicSetupView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { destination = nil } } }
            }
            case .grid: NavigationStack { GridLayoutView() }
            case .sounds, .addSounds:
                if #available(iOS 18.0, *) {
                    soundLibrary(quickAdding: choice == .addSounds).presentationSizing(.page)
                } else {
                    soundLibrary(quickAdding: choice == .addSounds).presentationDetents([.large])
                }
            }
        }
        .sheet(item: $editor, onDismiss: { suggestNewAppearance = true }) { pad in
            if #available(iOS 18.0, *) {
                PadEditor(pad: pad, deckId: store.selectedDeckId, suggestNewAppearance: suggestNewAppearance).presentationSizing(.page)
            } else {
                PadEditor(pad: pad, deckId: store.selectedDeckId, suggestNewAppearance: suggestNewAppearance)
            }
        }
        .sheet(item: $editDeck) { deck in
            if #available(iOS 18.0, *) { DeckEditor(deck: deck).presentationSizing(.page) }
            else { DeckEditor(deck: deck) }
        }
        .alert("Something needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: stopFeedback)
        .onChange(of: editor != nil || editDeck != nil || destination != nil || picker) { _, presented in store.interacting = presented }
#if DEBUG
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            DesignPreview.orient()
            switch DesignPreview.screen {
            case "pinned-pages", "pinned-pages-second":
                DesignPreview.configurePinnedPages(store)
                if DesignPreview.screen == "pinned-pages-second" {
                    pageMemory.select(1, deckID: store.selectedDeckId, capacity: 4, padCount: 16)
                }
            case "layout-sharing", "layout-import", "layout-export":
                DesignPreview.configureActions(store); destination = .sharing
            case "key-logic", "key-logic-editor":
                DesignPreview.configureKeyLogic(store)
                if DesignPreview.screen == "key-logic-editor" { editor = store.selectedDeck?.pads.first }
            case "actions", "switch-editor", "random-editor", "app-profile":
                DesignPreview.configureActions(store)
                if DesignPreview.screen == "switch-editor" { editor = store.selectedDeck?.pads.first }
                if DesignPreview.screen == "random-editor" { editor = store.selectedDeck?.pads.dropFirst().first }
                if DesignPreview.screen == "app-profile" { editDeck = store.selectedDeck }
            case "play": enterPlayMode()
            case "pages", "play-pages":
                DesignPreview.configurePages(store)
                if DesignPreview.screen == "play-pages" { enterPlayMode() }
            case "grid": destination = .grid
            case "audio": destination = .audio
            case "playback-check": await DesignPreview.checkPlayback(store)
            case "packs", "pack-detail", "sounds", "rename", "import", "bulk-import", "sound-selection", "add-sounds": destination = .sounds
            case "recording", "recording-trim": destination = .recording
            case "settings", "appearance": destination = .settings
            case "audio-setup": destination = .audioSetup
            case "music-setup": destination = .musicSetup
            case "updates", "changelog", "markdown": destination = .updates
            case "connection": destination = .connection
            case "editor": editor = store.selectedDeck?.pads.first
            case "new-button": editor = Pad()
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
    private func soundLibrary(quickAdding: Bool) -> some View {
        NavigationStack {
            LibraryView(quickAdding: quickAdding, onAssign: { clip in pendingClip = clip; destination = nil }, onAdded: { destination = nil })
                .navigationTitle(quickAdding ? "Add sounds" : "Sounds")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { destination = nil }.disabled(store.busy) } }
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
                    Text("Create decks, edit buttons, and play sounds on this iPad.").font(.subheadline).foregroundStyle(.secondary)
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
                        if store.selectedDeckId != deck.id { selectionFeedback += 1 }
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
                    Button("Share & import layouts", systemImage: "square.and.arrow.up") {
                        picker = false; sharingButton = nil; destination = .sharing
                    }
                    Button("New deck", systemImage: "plus") {
                        picker = false
                        editDeck = Deck()
                    }
                    }
                }
            }.navigationTitle("Your decks").navigationBarTitleDisplayMode(.inline)
        }.frame(minWidth: 320, idealWidth: 360, minHeight: 300, idealHeight: 420)
    }
    private func board(layout: BoardLayout) -> some View {
        let pads = store.selectedDeck?.pads ?? []
        let pagination = DeckPagination(pads: pads, capacity: layout.capacity)
        let pages = pagination.pageCount
        let page = pageMemory.page(deckID: store.selectedDeckId, capacity: pagination.pageCapacity, padCount: pagination.scrolling.count)
        let selection = Binding(get: {
            pageMemory.page(deckID: store.selectedDeckId, capacity: pagination.pageCapacity, padCount: pagination.scrolling.count)
        }, set: { value in
            pageMemory.select(value, deckID: store.selectedDeckId, capacity: pagination.pageCapacity, padCount: pagination.scrolling.count)
        })
        return VStack(spacing: 0) {
            if pads.isEmpty {
                ContentUnavailableView {
                    Label("Add your first button", systemImage: "square.grid.2x2")
                } description: { Text("Choose a sound, a shortcut, or something you do every day.") } actions: {
                    if playMode {
                        Button("Choose another deck") { picker = true }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Add sounds", systemImage: "plus") { destination = .addSounds }.buttonStyle(.borderedProminent)
                        Button("Create custom button") { editor = Pad() }.disabled(store.busy)
                    }
                }
            } else {
                TabView(selection: selection) {
                    ForEach(0..<pages, id: \.self) { number in
                        let shown = pagination.buttons(on: number)
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
                    Button { selectionFeedback += 1; withAnimation(reduceMotion ? nil : .default) { selection.wrappedValue = page - 1 } } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(page == 0).accessibilityLabel("Previous page")
                    Menu {
                        Picker("Page", selection: selection) {
                            ForEach(0..<pages, id: \.self) { number in
                                Text("\(number + 1) · \(pagination.label(on: number))").tag(number)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(page + 1) of \(pages)").monospacedDigit()
                            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                        }.font(.subheadline).frame(minWidth: 88, minHeight: 44)
                    }.accessibilityLabel("Page \(page + 1) of \(pages)")
                        .accessibilityHint("Choose a page, or swipe across the buttons")
                    Button { selectionFeedback += 1; withAnimation(reduceMotion ? nil : .default) { selection.wrappedValue = page + 1 } } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(page == pages - 1).accessibilityLabel("Next page")
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    @ViewBuilder private func tile(_ pad: Pad, pads: [Pad]) -> some View {
        let peers = pads.filter { $0.isPinned == pad.isPinned }
        let blocked = store.connected && store.snapshot.blocksDesktopAction(pad)
        if playMode {
            PadTile(pad: pad, active: store.activePad == pad.id, playing: store.playingPadIDs.contains(pad.id), queuePosition: store.queuePosition(for: pad.id), blocked: blocked, switched: store.switchedPadIDs.contains(pad.id), gestureAction: { trigger(pad, gesture: $0) }) {
                trigger(pad)
            }
        } else {
            PadTile(pad: pad, editing: store.editing, active: store.activePad == pad.id, playing: store.playingPadIDs.contains(pad.id), queuePosition: store.queuePosition(for: pad.id), blocked: blocked && !store.editing, switched: store.switchedPadIDs.contains(pad.id), gestureAction: { trigger(pad, gesture: $0) }) {
                if store.editing { editor = pad } else { trigger(pad) }
            }
            .modifier(PadReordering(enabled: store.editing, id: pad.id) { id in Task { await store.movePad(id, to: pad.id) } })
            .contextMenu {
                if pad.holdAction == nil || store.editing {
                if store.supportsPinnedPads {
                    Button(pad.isPinned ? "Unpin button" : "Pin to every page", systemImage: pad.isPinned ? "pin.slash" : "pin") {
                        Task { await store.setPinned(!pad.isPinned, pad: pad) }
                    }.disabled(store.busy)
                }
                Button("Edit button", systemImage: "pencil") { editor = pad }.disabled(store.busy)
                Button("Share button…", systemImage: "square.and.arrow.up") { sharingButton = pad; destination = .sharing }
                Button("Duplicate button", systemImage: "plus.square.on.square") { suggestNewAppearance = false; editor = pad.duplicated() }
                    .disabled(pads.count >= 48)
                Button("Rearrange buttons", systemImage: "hand.draw") { store.editing = true }.disabled(store.busy)
                if let index = peers.firstIndex(where: { $0.id == pad.id }) {
                    if index > 0 {
                        Button("Move earlier", systemImage: "arrow.left") { Task { await store.movePad(pad.id, to: peers[index - 1].id) } }.disabled(store.busy)
                    }
                    if index + 1 < peers.count {
                        Button("Move later", systemImage: "arrow.right") { Task { await store.movePad(pad.id, to: peers[index + 1].id) } }.disabled(store.busy)
                    }
                }
                }
            }
        }
    }
    private func enterPlayMode() {
        selectionFeedback += 1
        withAnimation(reduceMotion ? nil : .snappy) { store.editing = false; playMode = true }
    }
    private func trigger(_ pad: Pad, gesture: PadGesture = .tap) {
        guard let selected = pad.resolved(for: gesture) else { return }
        if store.connected && store.snapshot.blocksDesktopAction(selected) {
            store.error = "Your PC is in Soundboard mode. Sounds still work. To use desktop actions, turn off Soundboard mode in the Windows companion’s Controls tab. Check your game’s rules before using keyboard shortcuts or sequences."
        } else {
            Task { await store.trigger(pad, gesture: gesture) }
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
                        Text(store.connected && !store.supportsPlayback ? "Sound controls" : store.effectiveSoundMode.label + (store.queuedPadIDs.isEmpty ? "" : " · \(store.queuedPadIDs.count) queued"))
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
        Button { stopFeedback += 1; Task { await store.stopAll() } } label: {
            Label("Stop all", systemImage: "stop.fill").font(.body.weight(.medium)).padding(.horizontal, 20).padding(.vertical, 15)
        }.foregroundStyle(.primary).background(Palette.panel, in: Capsule()).buttonStyle(PadPressStyle())
    }
}

#Preview { ContentView().environment(RiffStore()).tint(Palette.accent) }
