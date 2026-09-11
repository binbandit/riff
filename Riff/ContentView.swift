import SwiftUI
import UniformTypeIdentifiers

@main struct RiffApp: App {
    @State private var store = RiffStore()
    var body: some Scene {
        WindowGroup { ContentView().environment(store).preferredColorScheme(.dark).tint(Palette.accent) }
    }
}

struct ContentView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var destination: Destination?
    @State private var editor: Pad?
    @State private var editDeck: Deck?
    @State private var library = false
    enum Destination: String, Identifiable { case connection, recording, settings; var id: String { rawValue } }

    var body: some View {
        @Bindable var store = store
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width > 740 { sidebar.frame(width: 222) }
                VStack(alignment: .leading, spacing: 0) {
                    if geometry.size.width <= 740 { compactHeader }
                    topBar
                    if library { LibraryView(onAssign: { clip in editor = Pad(title: clip.name, icon: "waveform", value: clip.id) }) }
                    else { deckBody }
                    bottomBar
                }
                .padding(.horizontal, geometry.size.width > 740 ? 32 : 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Palette.background)
        }
        .sheet(item: $destination) { choice in
            switch choice {
            case .connection: ConnectionView()
            case .recording: RecordingView { clip in editor = Pad(title: clip.name, icon: "waveform", value: clip.id) }
            case .settings: SettingsView()
            }
        }
        .sheet(item: $editor) { pad in PadEditor(pad: pad, deckId: store.selectedDeckId) }
        .sheet(item: $editDeck) { deck in DeckEditor(deck: deck) }
        .alert("Something needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.1)))
                    .padding(.bottom, 98).allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toast)
        .onChange(of: editor != nil || editDeck != nil || destination != nil) { _, presented in store.interacting = presented }
        .task(id: scenePhase) {
            UIApplication.shared.isIdleTimerDisabled = scenePhase == .active
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.system(size: 29, weight: .bold)).foregroundStyle(Palette.accent)
                Text("riff").font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1.5)
                Text("DECK").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.secondary).padding(.top, 10)
            }.padding(.top, 30).padding(.bottom, 42)
            eyebrow("YOUR SPACE").padding(.bottom, 16)
            sidebarButton("Sound library", icon: "square.stack", selected: library) { library = true; store.editing = false }
            HStack {
                eyebrow("DECKS")
                Spacer()
                Button { editDeck = Deck() } label: { Image(systemName: "plus").font(.system(size: 13, weight: .semibold)) }
                    .disabled(!store.connected).accessibilityLabel("Create deck")
            }.padding(.top, 30).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.snapshot.decks) { deck in
                        sidebarButton(deck.name, icon: deck.icon, selected: !library && store.selectedDeckId == deck.id) {
                            library = false; store.selectedDeckId = deck.id
                        }.contextMenu {
                            Button("Edit deck", systemImage: "pencil") { editDeck = deck }.disabled(!store.connected)
                        }
                    }
                }
            }.scrollIndicators(.hidden)
            if !store.snapshot.activeGameName.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("NOW PLAYING", systemImage: "gamecontroller.fill").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(Palette.color("green"))
                    Text(store.snapshot.activeGameName).font(.subheadline.weight(.medium)).lineLimit(2)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Palette.raised, in: RoundedRectangle(cornerRadius: 14)).padding(.bottom, 18)
            }
            sidebarButton("Settings", icon: "slider.horizontal.3", selected: false) { destination = .settings }
            Button { destination = .connection } label: {
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.connected ? store.snapshot.computerName : "Connect your PC").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 5) {
                            Circle().fill(store.connected ? Palette.color("green") : .gray).frame(width: 5, height: 5)
                            Text(store.connected ? "Ready to play" : store.paired ? "Reconnecting…" : "Pair in a moment").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 20)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).background(Palette.panel)
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.055)).frame(width: 1) }
    }
    private func sidebarButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 22)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if selected { RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 3, height: 16) }
            }
            .foregroundStyle(selected ? Palette.accent : Color.white.opacity(0.6))
            .padding(.horizontal, 12).padding(.vertical, 14)
            .background(selected ? Palette.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
    }
    private var compactHeader: some View {
        HStack {
            Text("riff").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Palette.accent)
            Spacer()
            Menu {
                ForEach(store.snapshot.decks) { deck in Button(deck.name, systemImage: deck.icon) { store.selectedDeckId = deck.id; library = false } }
                Button("Sound library", systemImage: "square.stack") { library = true }
                Button("New deck", systemImage: "plus") { editDeck = Deck() }.disabled(!store.connected)
                Button("Settings", systemImage: "slider.horizontal.3") { destination = .settings }
                Button("Connect PC", systemImage: "desktopcomputer") { destination = .connection }
            } label: { Label("Your space", systemImage: "sidebar.left") }
        }.padding(.top, 12)
    }
    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 9) {
                eyebrow(library ? "A LITTLE NOISE. A LOT OF PERSONALITY." : store.editing ? "MAKE IT YOURS" : "YOUR MOMENT. ON CUE.")
                Text(library ? "Sound library" : store.selectedDeck?.name ?? "Your deck")
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-1)
            }
            Spacer(minLength: 12)
            if !library {
                Button { withAnimation { store.editing.toggle() } } label: {
                    Label(store.editing ? "Done" : "Edit deck", systemImage: store.editing ? "checkmark" : "slider.horizontal.3")
                }.buttonStyle(QuietButtonStyle()).disabled(!store.connected)
            }
            Button { destination = .recording } label: { Label("Record", systemImage: "mic.fill") }
                .buttonStyle(AccentButtonStyle()).disabled(!store.connected)
        }.padding(.top, 32).padding(.bottom, 26)
    }
    private var deckBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !store.connected {
                    Button { destination = .connection } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "personalhotspot").font(.title2).foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.paired ? "Your PC is offline" : "Your iPad. Your new control room.").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Text(store.paired ? (store.connectionIssue ?? "Open Riff on your PC. We’ll reconnect automatically.") : "Try a sound below, then connect your PC to take it live.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(Palette.accent)
                        }.padding(20).background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.accent.opacity(0.2)))
                    }.buttonStyle(.plain)
                }
                HStack {
                    HStack(spacing: 7) {
                        Circle().fill(store.editing ? Palette.accent : store.connected ? Palette.color("green") : .gray).frame(width: 6, height: 6)
                        Text(store.editing ? "Drag buttons to rearrange. Tap to customize." : store.connected ? "Tap a button. Make something happen." : "Preview mode · Sounds play on this iPad")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.editing {
                        Button("Deck settings") { editDeck = store.selectedDeck }.font(.caption.weight(.medium))
                    } else { Text("\(store.selectedDeck?.pads.count ?? 0) BUTTONS").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(.tertiary) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: sizeClass == .compact ? 2 : store.columns), spacing: 16) {
                    ForEach(Array((store.selectedDeck?.pads ?? []).enumerated()), id: \.element.id) { index, pad in
                        PadTile(pad: pad, index: index + 1, editing: store.editing, active: store.activePad == pad.id) {
                            if store.editing { editor = pad } else { Task { await store.trigger(pad) } }
                        }
                        .draggable(store.editing ? pad.id : "")
                        .dropDestination(for: String.self) { ids, _ in
                            guard store.editing, let id = ids.first, !id.isEmpty else { return false }
                            Task { await store.movePad(id, to: pad.id) }; return true
                        }
                        .contextMenu {
                            Button("Edit button", systemImage: "pencil") { editor = pad }.disabled(!store.connected)
                            if index > 0 {
                                Button("Move earlier", systemImage: "arrow.left") {
                                    if let pads = store.selectedDeck?.pads { Task { await store.movePad(pad.id, to: pads[index - 1].id) } }
                                }.disabled(!store.connected)
                            }
                            if index + 1 < (store.selectedDeck?.pads.count ?? 0) {
                                Button("Move later", systemImage: "arrow.right") {
                                    if let pads = store.selectedDeck?.pads { Task { await store.movePad(pad.id, to: pads[index + 1].id) } }
                                }.disabled(!store.connected)
                            }
                        }
                    }
                    Button { editor = Pad() } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "plus").font(.system(size: 26, weight: .light))
                            Text("Add a button").font(.system(size: 12, weight: .medium))
                        }.foregroundStyle(.white.opacity(0.32)).frame(maxWidth: .infinity).frame(height: 155)
                        .background(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.13), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
                    }.buttonStyle(.plain).disabled(!store.connected || (store.selectedDeck?.pads.count ?? 0) >= 48)
                }
                if let deck = store.selectedDeck, !deck.steamAppId.isEmpty {
                    Label("Linked to \(store.snapshot.games.first(where: { $0.id == deck.steamAppId })?.name ?? "Steam game \(deck.steamAppId)")", systemImage: "gamecontroller")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 28)
        }.scrollIndicators(.hidden)
    }
    private var bottomBar: some View {
        HStack(spacing: 16) {
            Image(systemName: store.cableSelected ? "mic.badge.waveform" : "speaker.wave.2").font(.system(size: 22)).foregroundStyle(Palette.accent)
            Button { destination = .settings } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.connected ? "SOUND OUTPUT" : "LISTEN LOCALLY").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(.tertiary)
                    HStack(spacing: 6) {
                        Text(store.connected ? store.outputName : "iPad preview").font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }.foregroundStyle(.white.opacity(0.8))
                }
            }.buttonStyle(.plain)
            Spacer()
            if store.connected { Text("\(Int(store.snapshot.volume * 100))%").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
            Button { Task { await store.stopAll() } } label: { Label("Stop all", systemImage: "stop.fill") }
                .buttonStyle(QuietButtonStyle()).accessibilityHint("Stops every playing sound and running sequence on your PC")
        }.padding(.vertical, 22).overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }
}

struct PadTile: View {
    let pad: Pad
    var index = 1
    var editing = false
    var active = false
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(String(format: "%02d", index)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.24))
                    Spacer()
                    if editing { Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(pad.tint) }
                    else if active { ProgressView().controlSize(.mini).tint(pad.tint) }
                    else { Circle().fill(pad.tint.opacity(0.65)).frame(width: 4, height: 4) }
                }
                Spacer(minLength: 10)
                Image(systemName: pad.icon).font(.system(size: 32, weight: .light)).foregroundStyle(pad.tint).frame(height: 38)
                Spacer(minLength: 14)
                Text(pad.title).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.92)).lineLimit(1)
                Text(pad.kind == "sound" ? "SOUNDBOARD" : pad.typeName.uppercased()).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundStyle(pad.tint.opacity(0.6)).padding(.top, 6)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading).frame(height: 155)
            .background(LinearGradient(colors: [pad.tint.opacity(active ? 0.23 : 0.11), Palette.panel], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(pad.tint.opacity(active ? 0.7 : 0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 7, y: 4)
        }
        .buttonStyle(PadPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: active)
        .accessibilityLabel("\(pad.title), \(pad.typeName)")
        .accessibilityHint(editing ? "Edit this button. Use the actions menu to move it." : "Run this action")
    }
}
struct PadPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.07 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 16).padding(.vertical, 13).background(.white.opacity(configuration.isPressed ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.07)))
    }
}
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.background)
            .padding(.horizontal, 18).padding(.vertical, 13).background(Palette.accent.opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.3), in: RoundedRectangle(cornerRadius: 11))
    }
}
func eyebrow(_ text: String) -> some View {
    Text(text).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.6).foregroundStyle(.white.opacity(0.32))
}
#Preview { ContentView().environment(RiffStore()).preferredColorScheme(.dark).tint(Palette.accent) }
