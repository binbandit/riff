import SwiftUI

struct PadEditor: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var pad: Pad
    let deckId: String
    @State private var saving = false
    @State private var failure: String?
    @State private var confirmDelete = false
    private let icons = ["sparkles", "waveform", "theatermasks", "hand.raised", "timer", "circle.circle", "light.beacon.max", "gamecontroller", "bolt", "heart", "star", "speaker.wave.2", "mic", "playpause", "forward.end", "command", "desktopcomputer", "viewfinder", "text.bubble", "globe", "app", "square.stack.3d.up", "speaker.slash", "flame"]
    var body: some View {
        NavigationStack {
            Form {
                Section { HStack { Spacer(); PadTile(pad: pad).frame(width: 210).disabled(true); Spacer() }.listRowBackground(Color.clear) }
                Section("Make it yours") {
                    TextField("Button name", text: $pad.title)
                    HStack(spacing: 18) {
                        ForEach(Palette.colors, id: \.self) { color in
                            Button { pad.color = color } label: {
                                Circle().fill(Palette.color(color)).frame(width: 32, height: 32)
                                    .overlay { if pad.color == color { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black) } }
                            }.buttonStyle(.plain).accessibilityLabel("\(color) button color").accessibilityAddTraits(pad.color == color ? .isSelected : [])
                        }
                    }.padding(.vertical, 5)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 14) {
                        ForEach(icons, id: \.self) { icon in
                            Button { pad.icon = icon } label: {
                                Image(systemName: icon).font(.system(size: 20)).frame(width: 40, height: 40)
                                    .foregroundStyle(pad.icon == icon ? pad.tint : .gray)
                                    .background(pad.icon == icon ? pad.tint.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
                        }
                    }.padding(.vertical, 8)
                }
                Section("What happens when you tap") {
                    Picker("Action", selection: $pad.kind) { ForEach(ActionKind.allCases) { kind in Label(kind.label, systemImage: kind.icon).tag(kind.rawValue) } }
                    ActionFields(kind: pad.kind, value: $pad.value)
                }
                if pad.kind == "macro" {
                    Section {
                        ForEach($pad.steps) { $step in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("STEP \((pad.steps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1)").font(.caption.monospaced()).foregroundStyle(.secondary)
                                    Spacer()
                                    if let index = pad.steps.firstIndex(where: { $0.id == step.id }), index > 0 { Button { pad.steps.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }.accessibilityLabel("Move step earlier") }
                                    Button(role: .destructive) { pad.steps.removeAll { $0.id == step.id } } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove step")
                                }.buttonStyle(.borderless)
                                Picker("Action", selection: $step.kind) {
                                    ForEach(ActionKind.allCases.filter { $0 != .macro }) { Text($0.label).tag($0.rawValue) }
                                }.onChange(of: step.kind) { _, kind in step.value = defaultValue(kind) }
                                ActionFields(kind: step.kind, value: $step.value)
                                Stepper("Wait before: \(step.delayMs) ms", value: $step.delayMs, in: 0...5000, step: 100).font(.subheadline)
                            }.padding(.vertical, 8)
                        }
                        Button("Add step", systemImage: "plus") { pad.steps.append(ActionStep()) }.disabled(pad.steps.count >= 20)
                    } header: { Text("Sequence") } footer: { Text("Steps run in order. Stop all cancels remaining steps. Use up to 20 steps and 30 seconds of total delays.") }
                }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
                if store.snapshot.decks.flatMap(\.pads).contains(where: { $0.id == pad.id }) {
                    Section { Button("Delete button", role: .destructive) { confirmDelete = true } }
                }
            }
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Customize button").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }.fontWeight(.semibold).disabled(saving || pad.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: pad.kind) { _, kind in
                pad.value = defaultValue(kind); pad.steps = kind == "macro" ? [ActionStep()] : []
                pad.icon = ActionKind(rawValue: kind)?.icon ?? "sparkles"
            }
            .confirmationDialog("Delete this button?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete button", role: .destructive) {
                    var decks = store.snapshot.decks
                    if let index = decks.firstIndex(where: { $0.id == deckId }) { decks[index].pads.removeAll { $0.id == pad.id } }
                    saving = true
                    Task { do { try await store.saveDecks(decks); dismiss() } catch { failure = error.localizedDescription }; saving = false }
                }
            }
        }.interactiveDismissDisabled(saving)
    }
    private func defaultValue(_ kind: String) -> String {
        switch kind {
        case "sound": store.snapshot.clips.first?.id ?? ""
        case "media": "playPause"
        case "hotkey": "Ctrl+Shift+M"
        case "app": store.snapshot.apps.first?.id ?? ""
        case "url": "https://"
        default: ""
        }
    }
    private func save() {
        saving = true; failure = nil; pad.title = pad.title.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { do { try await store.savePad(pad, in: deckId); dismiss() } catch { failure = error.localizedDescription }; saving = false }
    }
}

struct ActionFields: View {
    @Environment(RiffStore.self) private var store
    let kind: String
    @Binding var value: String
    var body: some View {
        switch kind {
        case "sound":
            Picker("Sound", selection: $value) { ForEach(store.snapshot.clips) { Text($0.name).tag($0.id) } }
            Text("Plays through the output selected in Audio settings. For game chat, choose your virtual cable.").font(.caption).foregroundStyle(.secondary)
        case "hotkey":
            TextField("Ctrl+Shift+M", text: $value).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("Use Ctrl, Alt, Shift, Win, letters, digits, F1-F24, or names like Space and Enter. The shortcut goes to the focused Windows app.").font(.caption).foregroundStyle(.secondary)
        case "text":
            TextField("Text to type", text: $value, axis: .vertical).lineLimit(3...6)
            Text("Types into the focused field on your PC. Add an Enter shortcut as the next sequence step if you want to send it.").font(.caption).foregroundStyle(.secondary)
        case "url": TextField("https://example.com", text: $value).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        case "app":
            if store.snapshot.apps.isEmpty { Text("On your PC, open Riff > Allowed apps and add an application first.").font(.subheadline).foregroundStyle(.secondary) }
            else { Picker("Application", selection: $value) { ForEach(store.snapshot.apps) { Text($0.name).tag($0.id) } } }
        case "media":
            Picker("Control", selection: $value) {
                Text("Play / pause").tag("playPause"); Text("Next track").tag("next"); Text("Previous track").tag("previous")
                Text("Volume up").tag("volumeUp"); Text("Volume down").tag("volumeDown"); Text("Mute / unmute").tag("mute")
            }
        default: EmptyView()
        }
    }
}

struct DeckEditor: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var deck: Deck
    @State private var failure: String?
    @State private var saving = false
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Your deck") {
                    TextField("Deck name", text: $deck.name)
                    Picker("Icon", selection: $deck.icon) {
                        Label("Soundboard", systemImage: "waveform").tag("waveform")
                        Label("Gaming", systemImage: "gamecontroller").tag("gamecontroller")
                        Label("Shortcuts", systemImage: "command").tag("command")
                        Label("Workspace", systemImage: "square.grid.2x2").tag("square.grid.2x2")
                        Label("Streaming", systemImage: "video").tag("video")
                    }
                }
                Section {
                    Picker("Linked game", selection: $deck.steamAppId) {
                        Text("None - choose this deck manually").tag("")
                        ForEach(store.snapshot.games) { Text($0.name).tag($0.id) }
                        if !deck.steamAppId.isEmpty && !store.snapshot.games.contains(where: { $0.id == deck.steamAppId }) { Text("Steam game \(deck.steamAppId)").tag(deck.steamAppId) }
                    }
                    TextField("Or enter a Steam app ID", text: $deck.steamAppId).keyboardType(.numberPad)
                } header: { Text("Follow your game") } footer: {
                    Text("Riff finds installed Steam games on your PC. With automatic switching enabled in Settings, this deck opens when Steam reports the game running. If multiple games run at once, choose a deck manually.")
                }
                if let failure { Text(failure).foregroundStyle(.red) }
                if store.snapshot.decks.contains(where: { $0.id == deck.id }) {
                    Section {
                        Button("Duplicate deck", systemImage: "square.on.square") {
                            var duplicate = deck; duplicate.id = UUID().uuidString; duplicate.name = String((deck.name + " copy").prefix(40)); duplicate.steamAppId = ""
                            duplicate.pads = duplicate.pads.map { var pad = $0; pad.id = UUID().uuidString; return pad }
                            persist(store.snapshot.decks + [duplicate], selected: duplicate.id)
                        }
                        Button("Delete deck", role: .destructive) { confirmDelete = true }.disabled(store.snapshot.decks.count <= 1)
                    }
                }
            }.disabled(saving).scrollContentBackground(.hidden).background(Palette.background)
                .navigationTitle("Deck settings").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Save") {
                            var decks = store.snapshot.decks
                            if let index = decks.firstIndex(where: { $0.id == deck.id }) {
                                // Keep current pads when saving deck metadata after another edit.
                                deck.pads = decks[index].pads; decks[index] = deck
                            } else { decks.append(deck) }
                            persist(decks, selected: deck.id)
                        }.disabled(saving || deck.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .confirmationDialog("Delete this deck and its buttons? Your sounds stay in the library.", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete deck", role: .destructive) { persist(store.snapshot.decks.filter { $0.id != deck.id }, selected: nil) }
                }
        }.interactiveDismissDisabled(saving)
    }
    private func persist(_ decks: [Deck], selected: String?) {
        saving = true
        Task { do { try await store.saveDecks(decks); if let selected { store.selectedDeckId = selected }; dismiss() } catch { failure = error.localizedDescription }; saving = false }
    }
}
