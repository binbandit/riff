import SwiftUI

struct PadEditor: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var pad: Pad
    let deckId: String
    @State private var targetDeckId: String?
    @State private var saving = false
    @State private var failure: String?
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 22) {
                        PadTile(pad: pad).frame(width: 130, height: 130).disabled(true)
                        VStack(alignment: .leading, spacing: 14) {
                            TextField("Button name", text: $pad.title).font(.title3.weight(.semibold))
                            if pad.title.utf16.count > 40 { Text("Use 40 characters or fewer.").font(.caption).foregroundStyle(.red) }
                            NavigationLink { PadAppearanceEditor(pad: $pad) } label: {
                                Label("Icon & color", systemImage: "paintpalette").font(.subheadline)
                            }
                        }
                    }.padding(.vertical, 10)
                }
                Section {
                    Picker("Deck", selection: Binding(get: { targetDeckId ?? deckId }, set: { targetDeckId = $0 })) {
                        ForEach(store.snapshot.decks) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    if (targetDeckId ?? deckId) != deckId && store.snapshot.decks.flatMap(\.pads).contains(where: { $0.id == pad.id }) {
                        Text("This button moves to the selected deck when you save. To keep both, cancel and choose Duplicate button instead.")
                    }
                }
                Section("Action") {
                    Picker("Action", selection: $pad.kind) { ForEach(ActionKind.allCases) { kind in Label(kind.label, systemImage: kind.icon).tag(kind.rawValue) } }
                    ActionFields(kind: pad.kind, value: $pad.value)
                }
                if pad.kind == "macro" {
                    Section {
                        ForEach($pad.steps) { $step in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Step \((pad.steps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
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
            .disabled(saving)
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle(store.snapshot.decks.flatMap(\.pads).contains(where: { $0.id == pad.id }) ? "Edit button" : "Add button").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }.fontWeight(.semibold).disabled(saving || !store.connected || store.busy || pad.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pad.title.utf16.count > 40)
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
        Task { do { try await store.savePad(pad, in: targetDeckId ?? deckId); dismiss() } catch { failure = error.localizedDescription }; saving = false }
    }
}
