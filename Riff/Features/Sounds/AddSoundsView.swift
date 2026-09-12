import SwiftUI

struct AddSoundsView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let clipIDs: [String]
    var suggestedName: String? = nil
    let onAdded: () -> Void
    @State private var targetID = ""
    @State private var newDeckID = UUID().uuidString
    @State private var name = ""
    @State private var icon = "waveform"
    @State private var saving = false
    @State private var failure: String?
    @State private var initialized = false
    @State private var useAI = true
    @State private var suggestions: [String: PadSuggestion] = [:]
    @State private var suggestedContext: SoundSuggestionRequest?
    @State private var manualEdits: [String: SoundButtonEdits] = [:]
    @State private var loading = false
    @State private var suggestionError: String?
    @State private var retry = 0
    @State private var editingClip: Clip?
    private struct SuggestionTask: Hashable {
        let request: SoundSuggestionRequest?
        let retry: Int
    }
    private var suggestionContext: SoundSuggestionRequest? {
        guard case .success(let plan) = addition, !plan.added.isEmpty else { return nil }
        let deck = plan.decks.first { $0.id == plan.deckID }
        return SoundSuggestionRequest(clipIds: plan.added.map(\.id), deckName: deck?.name ?? "",
                                      gameId: deck?.steamAppId ?? "", appId: deck?.linkedAppId ?? "")
    }
    private var request: SoundSuggestionRequest? {
        useAI && store.padSuggestionsEnabled && store.supportsSoundSuggestions && !saving ? suggestionContext : nil
    }
    private var target: SoundDeckTarget {
        targetID.isEmpty ? .new(id: newDeckID, name: name, icon: icon) : .existing(targetID)
    }
    private var addition: Result<SoundDeckAddition, Error> {
        Result { try SoundDeckAddition(snapshot: store.snapshot, clipIDs: clipIDs, target: target) }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Add to", selection: $targetID) {
                        Text("New deck").tag("")
                        ForEach(store.snapshot.decks) { deck in
                            Text("\(deck.name) · \(48 - deck.pads.count) spaces").tag(deck.id)
                        }
                    }
                    if targetID.isEmpty {
                        TextField("Deck name", text: $name, prompt: Text("e.g. Pilot calls or Memes"))
                            .textInputAutocapitalization(.words)
                        Picker("Icon", selection: $icon) {
                            Label("Sounds", systemImage: "waveform").tag("waveform")
                            Label("Flying", systemImage: "airplane").tag("airplane")
                            Label("Gaming", systemImage: "gamecontroller").tag("gamecontroller")
                            Label("Just for fun", systemImage: "face.smiling").tag("face.smiling")
                        }
                    }
                } header: { Text("Choose a home for your sounds") } footer: {
                    Text("Buttons follow the order you selected them. Edit a label or tap an icon to make it your own.")
                }
                aiSection
                switch addition {
                case .success(let plan):
                    Section {
                        ForEach(plan.added) { clip in
                            let button = buttonBinding(for: clip, plan: plan)
                            HStack(spacing: 14) {
                                Button { editingClip = clip } label: {
                                    PadGlyph(icon: button.wrappedValue.icon, size: 24)
                                        .foregroundStyle(Palette.ink).frame(width: 48, height: 48)
                                        .background(button.wrappedValue.tint, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityLabel("Icon and color for \(clip.name)")
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("Button label", text: button.title)
                                        .accessibilityLabel("Button label for \(clip.name)")
                                    Text(clip.name).font(.caption).foregroundStyle(.secondary)
                                    if button.wrappedValue.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || button.wrappedValue.title.utf16.count > 40 {
                                        Text("Use a label of 1–40 characters.").font(.caption).foregroundStyle(.red)
                                    }
                                }
                                Spacer()
                                Text(String(format: "%.1fs", clip.duration)).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                        if plan.added.isEmpty { Text("These sounds already have buttons on this deck.").foregroundStyle(.secondary) }
                    } header: { Text("\(plan.added.count) new buttons") } footer: {
                        if plan.skipped > 0 { Text("\(plan.skipped) already on this deck. Their buttons stay as they are.") }
                    }
                case .failure(let error):
                    if !targetID.isEmpty || !name.isEmpty {
                        Section { Text(error.localizedDescription).foregroundStyle(.secondary) }
                    } else {
                        Section { Text("\(clipIDs.count) sounds ready. Name your new deck to continue.").foregroundStyle(.secondary) }
                    }
                }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Add sounds to deck").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Adding…" : targetID.isEmpty ? "Create deck" : "Add buttons") { save() }
                        .fontWeight(.semibold).disabled(!canSave)
                }
            }
            .navigationDestination(item: $editingClip) { clip in
                if case .success(let plan) = addition {
                    let button = buttonBinding(for: clip, plan: plan)
                    PadAppearanceEditor(pad: button, onIconChange: {
                        manualEdits[clip.id, default: SoundButtonEdits()].icon = button.wrappedValue.icon
                    }, onColorChange: {
                        manualEdits[clip.id, default: SoundButtonEdits()].color = button.wrappedValue.color
                    })
                }
            }
            .onAppear {
                guard !initialized else { return }; initialized = true
                targetID = suggestedName == nil ? store.selectedDeckId : ""
                if let suggestedName { name = suggestedName }
            }
#if DEBUG
            .task {
                if DesignPreview.screen == "add-sounds" { targetID = ""; name = "Game night"; icon = "gamecontroller" }
            }
#endif
        }
        .task(id: SuggestionTask(request: request, retry: retry)) { await suggest() }
        .interactiveDismissDisabled(saving)
    }
    @ViewBuilder private var aiSection: some View {
        Section {
            Toggle("AI suggestions", isOn: $useAI)
            if useAI {
                if !store.connected {
                    Text("Connect your PC for AI suggestions. You can still add your sounds now.").font(.footnote).foregroundStyle(.secondary)
                } else if !store.supportsSoundSuggestions || !store.padSuggestionsEnabled {
                    Text("Enable AI suggestions in the updated Windows companion’s Controls tab.").font(.footnote).foregroundStyle(.secondary)
                } else if loading {
                    HStack { ProgressView(); Text("Choosing labels, icons, and colors…").font(.subheadline) }
                } else if let suggestionError {
                    Text(suggestionError).font(.footnote).foregroundStyle(.secondary)
                    Button("Try suggestions again") { retry += 1 }.disabled(request == nil)
                } else if suggestedContext == suggestionContext, !suggestions.isEmpty {
                    Label("Suggested for your sounds", systemImage: "sparkles").font(.subheadline).foregroundStyle(.secondary)
                    Button("Suggest again") { retry += 1 }.disabled(request == nil)
                }
            }
        } footer: {
            Text("AI uses sound names and the deck’s game or app. Your edits stay in place, and you can add buttons without waiting.")
        }
    }
    private func button(for clip: Clip, plan: SoundDeckAddition) -> Pad {
        var pad = plan.decks.first { $0.id == plan.deckID }?.pads.last { $0.kind == "sound" && $0.value == clip.id }
            ?? Pad(title: clip.buttonTitle, icon: "waveform", value: clip.id)
        if useAI, suggestedContext == suggestionContext, let suggestion = suggestions[clip.id] {
            pad = PadSuggestionEdits().applying(suggestion, to: pad)
        }
        return (manualEdits[clip.id] ?? SoundButtonEdits()).applying(to: pad)
    }
    private func buttonBinding(for clip: Clip, plan: SoundDeckAddition) -> Binding<Pad> {
        Binding(get: { button(for: clip, plan: plan) }, set: { updated in
            let previous = button(for: clip, plan: plan)
            var edits = manualEdits[clip.id] ?? SoundButtonEdits()
            if previous.title != updated.title { edits.label = updated.title }
            if previous.icon != updated.icon { edits.icon = updated.icon }
            if previous.color != updated.color { edits.color = updated.color }
            manualEdits[clip.id] = edits
        })
    }
    private func suggest() async {
        loading = false; suggestionError = nil
        guard let pending = request else { return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(650))
            let result = try await store.suggestSoundAppearances(pending)
            try Task.checkCancellation()
            guard request == pending else { return }
            suggestions = result; suggestedContext = pending; loading = false
        } catch {
            guard !Task.isCancelled, request == pending else { return }
            loading = false
            suggestionError = error is CancellationError ? "The connection changed. Try suggestions again." : error.localizedDescription
        }
    }
    private var canSave: Bool {
        guard !store.busy, !saving, case .success(let plan) = addition else { return false }
        return !plan.added.isEmpty && plan.added.allSatisfy {
            let label = button(for: $0, plan: plan).title.trimmingCharacters(in: .whitespacesAndNewlines)
            return !label.isEmpty && label.utf16.count <= 40
        }
    }
    private func save() {
        guard case .success(let preview) = addition else { return }
        let appearances = Dictionary(uniqueKeysWithValues: preview.added.map { ($0.id, button(for: $0, plan: preview)) })
        saving = true; failure = nil
        Task {
            do {
                // Rebuild from the latest snapshot so existing buttons are never overwritten by a stale preview.
                let plan = try SoundDeckAddition(snapshot: store.snapshot, clipIDs: clipIDs, target: target, appearances: appearances)
                guard !plan.added.isEmpty else { saving = false; return }
                try await store.saveDecks(plan.decks)
                store.selectedDeckId = plan.deckID
                store.message("Added \(plan.added.count) sounds")
                onAdded(); dismiss()
            } catch { failure = error.localizedDescription }
            saving = false
        }
    }
}
