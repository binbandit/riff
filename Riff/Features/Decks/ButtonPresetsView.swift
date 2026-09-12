import SwiftUI

struct ButtonPresetsView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var deckID: String
    @State private var query = ""
    @State private var category: ButtonPresetCategory?
    @State private var selectedIDs: [String] = []
    @State private var chatKey = "K"
    @State private var saving = false
    @State private var failure: String?

    private var deck: Deck? { store.snapshot.decks.first { $0.id == deckID } }
    private var remaining: Int { max(0, 48 - (deck?.pads.count ?? 48)) }
    private var shown: [ButtonPreset] {
        ButtonPreset.all.filter { (category == nil || $0.category == category) && $0.matches(query) }
    }
    private var selectedChat: Bool {
        ButtonPreset.all.contains { $0.category == .chat && selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Add to", selection: $deckID) {
                        ForEach(store.snapshot.decks) { Text($0.name).tag($0.id) }
                    }
                    Picker("Category", selection: $category) {
                        Text("All presets").tag(Optional<ButtonPresetCategory>.none)
                        ForEach(ButtonPresetCategory.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    HStack {
                        Text("\(selectedIDs.count) selected · \(remaining) spaces available")
                            .foregroundStyle(selectedIDs.count > remaining ? .red : .secondary)
                        Spacer()
                        if !selectedIDs.isEmpty { Button("Clear") { selectedIDs.removeAll() } }
                    }.font(.subheadline)
                } footer: {
                    Text("Choose ready-made buttons and add them together. You can edit any button afterward. Shortcuts go to the focused Windows app.")
                }

                if store.snapshot.soundboardOnly == true {
                    Section {
                        Label("You can save PC controls now. Turn off Soundboard mode in the Windows companion to run them.", systemImage: "desktopcomputer")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if selectedChat || category == .chat {
                    Section {
                        Picker("Open chat with", selection: $chatKey) {
                            ForEach(ButtonPreset.chatKeys, id: \.self) { Text($0).tag($0) }
                        }
                    } header: { Text("Game chat setup") } footer: {
                        Text("Match your game's chat key. Each button opens chat, waits 300 ms, types its message, then presses Enter after 100 ms. Keep the game focused with chat closed. Edit the added button to change the message, key, or timing.")
                    }
                }

                if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(ButtonPresetCategory.allCases) { group in
                        let presets = shown.filter { $0.category == group }
                        if !presets.isEmpty {
                            Section(group.rawValue) {
                                ForEach(presets) { preset in presetRow(preset) }
                            }
                        }
                    }
                }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Button presets")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search presets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Adding…" : selectedIDs.isEmpty ? "Add" : "Add \(selectedIDs.count)") { add() }
                        .fontWeight(.semibold)
                        .disabled(saving || store.busy || store.connecting || deck == nil || selectedIDs.isEmpty || selectedIDs.count > remaining)
                        .accessibilityLabel("Add \(selectedIDs.count) buttons to \(deck?.name ?? "deck")")
                }
            }
        }.interactiveDismissDisabled(saving)
    }

    private func presetRow(_ preset: ButtonPreset) -> some View {
        let selected = selectedIDs.contains(preset.id)
        let unavailable = preset.unavailableReason(supportsDeckActions: store.supportsDeckActions)
        return Button {
            if selected { selectedIDs.removeAll { $0 == preset.id } }
            else { selectedIDs.append(preset.id) }
        } label: {
            HStack(spacing: 14) {
                PadGlyph(icon: preset.icon, size: 23)
                    .foregroundStyle(Palette.ink).frame(width: 46, height: 46)
                    .background(Palette.color(preset.color), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.title).font(.headline).foregroundStyle(.primary)
                    Text(unavailable ?? preset.detail).font(.subheadline).foregroundStyle(.secondary)
                    if preset.kind == .hotkey {
                        Text(preset.value).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? Palette.accent : .secondary)
            }.padding(.vertical, 5).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selected && (unavailable != nil || selectedIDs.count >= remaining))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func add() {
        saving = true; failure = nil
        Task {
            do {
                let decks = try PresetDeckBuilder.decks(adding: selectedIDs, to: deckID, snapshot: store.snapshot,
                                                       chatKey: chatKey, supportsDeckActions: store.supportsDeckActions)
                try await store.saveDecks(decks)
                store.selectedDeckId = deckID
                store.message("Added \(selectedIDs.count) \(selectedIDs.count == 1 ? "button" : "buttons")")
                dismiss()
            } catch { failure = error.localizedDescription }
            saving = false
        }
    }
}
