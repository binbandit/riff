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
                    Text("Buttons follow the order you selected them. You can rearrange them or change their names, icons, and colors later.")
                }
                switch addition {
                case .success(let plan):
                    Section {
                        ForEach(plan.added) { clip in
                            HStack(spacing: 14) {
                                Image(systemName: "waveform").foregroundStyle(Palette.accent)
                                Text(clip.buttonTitle)
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
                if !store.connected { Section { Text("Connect your PC to save these buttons.").foregroundStyle(.secondary) } }
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
            .onAppear {
                targetID = suggestedName == nil ? store.selectedDeckId : ""
                if let suggestedName { name = suggestedName }
            }
#if DEBUG
            .task {
                if DesignPreview.screen == "add-sounds" { targetID = ""; name = "Game night"; icon = "gamecontroller" }
            }
#endif
        }.interactiveDismissDisabled(saving)
    }
    private var canSave: Bool {
        guard store.connected, !store.busy, !saving, case .success(let plan) = addition else { return false }
        return !plan.added.isEmpty
    }
    private func save() {
        saving = true; failure = nil
        Task {
            do {
                // Rebuild from the latest snapshot so existing buttons are never overwritten by a stale preview.
                let plan = try SoundDeckAddition(snapshot: store.snapshot, clipIDs: clipIDs, target: target)
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
