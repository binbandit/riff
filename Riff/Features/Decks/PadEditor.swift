import SwiftUI

struct PadEditor: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var pad: Pad
    let deckId: String
    var suggestNewAppearance = true
    @State private var targetDeckId: String?
    @State private var saving = false
    @State private var failure: String?
    @State private var confirmDelete = false
    @State private var automaticSuggestions = true
    @State private var suggestionEdits = PadSuggestionEdits()
    @State private var suggesting = false
    @State private var suggestionMessage: String?
    @State private var suggestionFailure: String?
    @State private var suggestionRun = UUID()
    @State private var retry = 0
    private var isNew: Bool { !store.snapshot.decks.flatMap(\.pads).contains { $0.id == pad.id } }
    private var suggestionRequest: PadSuggestionRequest? {
        guard isNew, suggestNewAppearance, automaticSuggestions, store.padSuggestionsEnabled, !saving, !suggestionEdits.allEdited else { return nil }
        return PadSuggestionRequest(pad: pad, snapshot: store.snapshot, titleHint: suggestionEdits.label ? pad.title : "")
    }
    private struct SuggestionTask: Hashable { let request: PadSuggestionRequest?; let retry: Int }
    private var validSteps: Bool {
        guard ActionKind(rawValue: pad.kind)?.isSequence == true else { return true }
        let groups = pad.kind == "switch" ? [pad.steps, pad.alternateSteps ?? []] : [pad.steps]
        return groups.allSatisfy { !$0.isEmpty && $0.count <= 20 && $0.reduce(0, { $0 + $1.delayMs }) <= 30000 }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 22) {
                        PadTile(pad: pad).frame(width: 130, height: 130).disabled(true)
                        VStack(alignment: .leading, spacing: 14) {
                            TextField("Button name", text: Binding(get: { pad.title }, set: { suggestionEdits.label = true; pad.title = $0 })).font(.title3.weight(.semibold))
                            if pad.title.utf16.count > 40 { Text("Use 40 characters or fewer.").font(.caption).foregroundStyle(.red) }
                            NavigationLink { PadAppearanceEditor(pad: $pad, onIconChange: { suggestionEdits.icon = true }, onColorChange: { suggestionEdits.color = true }) } label: {
                                Label("Icon & color", systemImage: "paintpalette").font(.subheadline)
                            }
                        }
                    }.padding(.vertical, 10)
                }
                if isNew && suggestNewAppearance { suggestionSection }
                Section {
                    Picker("Deck", selection: Binding(get: { targetDeckId ?? deckId }, set: { targetDeckId = $0 })) {
                        ForEach(store.snapshot.decks) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    if (targetDeckId ?? deckId) != deckId && store.snapshot.decks.flatMap(\.pads).contains(where: { $0.id == pad.id }) {
                        Text("This button moves to the selected deck when you save. To keep both, cancel and choose Duplicate button instead.")
                    }
                }
                Section(pad.hasKeyLogic ? "Tap" : "Action") {
                    Picker("Action", selection: $pad.kind) { ForEach(store.availableActionKinds) { kind in Label(kind.label, systemImage: kind.icon).tag(kind.rawValue) } }
                    ActionFields(kind: pad.kind, value: $pad.value)
                }
                if store.supportsPinnedPads {
                    Section {
                        Toggle("Pin to every page", isOn: Binding(get: { pad.isPinned }, set: { pad.pinned = $0 ? true : nil }))
                    } footer: {
                        Text("Pinned buttons occupy the first slots on each page. If your grid is too small, extra pinned buttons appear on regular pages so every button stays reachable.")
                    }
                }
                if ActionKind(rawValue: pad.kind)?.isSequence == true {
                    SequenceEditor(steps: $pad.steps, title: pad.kind == "switch" ? "First press" : pad.kind == "random" ? "Choices" : "Sequence", random: pad.kind == "random")
                    if pad.kind == "switch" {
                        SequenceEditor(steps: Binding(get: { pad.alternateSteps ?? [] }, set: { pad.alternateSteps = $0 }), title: "Second press")
                        Section {
                            Text("Alternates between these two sequences after each successful run. The 1 / 2 badge shows which sequence runs next. Stopping or failing a sequence keeps the same side. Editing this button or restarting the companion resets it to the first press.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if store.supportsKeyLogic || pad.hasKeyLogic {
                    gestureSection(.doubleTap, action: $pad.doubleTapAction)
                    gestureSection(.hold, action: $pad.holdAction)
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
                    Button(saving ? "Saving…" : "Save") { save() }.fontWeight(.semibold).disabled(saving || store.busy || !validSteps || pad.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pad.title.utf16.count > 40)
                }
            }
            .onChange(of: pad.kind) { _, kind in
                pad.value = defaultValue(kind); pad.steps = ActionKind(rawValue: kind)?.isSequence == true ? [ActionStep()] : []
                pad.alternateSteps = kind == "switch" ? [ActionStep()] : nil
                if !suggestionEdits.icon { pad.icon = ActionKind(rawValue: kind)?.icon ?? "sparkles" }
            }
            .task(id: SuggestionTask(request: suggestionRequest, retry: retry)) { await suggestAppearance() }
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
    private func gestureSection(_ gesture: PadGesture, action: Binding<PadGestureAction?>) -> some View {
        Section {
            Toggle("Enable \(gesture.label.lowercased())", isOn: Binding(get: { action.wrappedValue != nil }, set: {
                action.wrappedValue = $0 ? PadGestureAction(kind: "sound", value: store.snapshot.clips.first?.id ?? "") : nil
            }))
            if action.wrappedValue != nil {
                Picker("Action", selection: Binding(get: { action.wrappedValue?.kind ?? "sound" }, set: {
                    action.wrappedValue = PadGestureAction(kind: $0, value: defaultValue($0))
                })) {
                    ForEach(store.availableActionKinds.filter(\.isGestureAction)) { kind in
                        Label(kind.label, systemImage: kind.icon).tag(kind.rawValue)
                    }
                }
                ActionFields(kind: action.wrappedValue?.kind ?? "sound", value: Binding(get: { action.wrappedValue?.value ?? "" }, set: { action.wrappedValue?.value = $0 }))
            }
        } header: { Text(gesture.label) } footer: {
            Text(gesture == .doubleTap
                 ? "Run a different action with two quick taps. A single tap waits briefly to distinguish it from a double-tap."
                 : "Hold for just over half a second to run this action once. Use Edit buttons in the deck menu to customize a button with a hold action.")
        }
    }
    private var suggestionSection: some View {
        Section {
            if store.padSuggestionsEnabled {
                Toggle(isOn: $automaticSuggestions) { Label("AI suggestions", systemImage: "sparkles") }
                if automaticSuggestions {
                    if suggesting {
                        HStack(spacing: 10) { ProgressView(); Text("Suggesting an appearance…").foregroundStyle(.secondary) }
                    } else if let suggestionFailure {
                        Text(suggestionFailure).font(.caption).foregroundStyle(.secondary)
                        Button("Try again", systemImage: "arrow.clockwise") { retry += 1 }
                    } else {
                        Text(suggestionEdits.allEdited ? "Using your custom appearance." : suggestionMessage ?? "Choose an action to suggest a label, icon, and color.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("AI suggestions", systemImage: "sparkles")
                Text(!store.connected ? "Connect your PC to use AI suggestions." : store.supportsPadSuggestions ? "Enable AI suggestions in the Windows companion's Controls tab." : "Update your Windows companion to set up AI suggestions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            if store.padSuggestionsEnabled && automaticSuggestions { Text("Action details are sent to OpenAI. Your manual choices are always kept.") }
        }
    }
    private func suggestAppearance() async {
        let run = UUID(); suggestionRun = run
        suggesting = false; suggestionFailure = nil; suggestionMessage = nil
        guard let request = suggestionRequest else { return }
        suggesting = true
        defer { if suggestionRun == run { suggesting = false } }
        do {
            try await Task.sleep(for: .milliseconds(650))
            let suggestion = try await store.suggestPadAppearance(request)
            guard !Task.isCancelled, suggestionRun == run, request == suggestionRequest else { return }
            pad = suggestionEdits.applying(suggestion, to: pad)
            suggestionMessage = "Appearance suggested. You can change anything."
        } catch {
            guard !Task.isCancelled, suggestionRun == run, request == suggestionRequest, !(error is CancellationError) else { return }
            suggestionFailure = error.localizedDescription
        }
    }
    private func defaultValue(_ kind: String) -> String {
        switch kind {
        case "sound": store.snapshot.clips.first?.id ?? ""
        case "media": "playPause"
        case "hotkey": "Ctrl+Shift+M"
        case "app": store.snapshot.apps.first?.id ?? ""
        case "deck": store.snapshot.decks.first(where: { $0.id != deckId })?.id ?? deckId
        case "url": "https://"
        default: ""
        }
    }
    private func save() {
        saving = true; failure = nil; pad.title = pad.title.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { do { try await store.savePad(pad, in: targetDeckId ?? deckId); dismiss() } catch { failure = error.localizedDescription }; saving = false }
    }
}
