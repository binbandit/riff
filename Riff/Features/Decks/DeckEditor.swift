import SwiftUI

struct DeckEditor: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var deck: Deck
    @State private var failure: String?
    @State private var saving = false
    @State private var confirmDelete = false
    private var cleanName: String { deck.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validName: Bool { !cleanName.isEmpty && cleanName.utf16.count <= 40 }
    var body: some View {
        NavigationStack {
            Form {
                Section("Your deck") {
                    TextField("Deck name", text: $deck.name)
                    if cleanName.utf16.count > 40 { Text("Use 40 characters or fewer.").font(.caption).foregroundStyle(.red) }
                    Picker("Icon", selection: $deck.icon) {
                        Label("Soundboard", systemImage: "waveform").tag("waveform")
                        Label("Gaming", systemImage: "gamecontroller").tag("gamecontroller")
                        Label("Flying", systemImage: "airplane").tag("airplane")
                        Label("Just for fun", systemImage: "face.smiling").tag("face.smiling")
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
                            var source = deck
                            source.pads = store.snapshot.decks.first(where: { $0.id == deck.id })?.pads ?? deck.pads
                            let duplicate = source.duplicated()
                            persist(store.snapshot.decks + [duplicate], selected: duplicate.id)
                        }.disabled(!validName || !store.connected || store.snapshot.decks.count >= 20)
                        Button("Delete deck", role: .destructive) { confirmDelete = true }.disabled(store.snapshot.decks.count <= 1)
                    }
                }
            }.disabled(saving).scrollContentBackground(.hidden).background(Palette.background)
                .navigationTitle("Deck settings").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Save") {
                            deck.name = cleanName
                            var decks = store.snapshot.decks
                            if let index = decks.firstIndex(where: { $0.id == deck.id }) {
                                // Keep current pads when saving deck metadata after another edit.
                                deck.pads = decks[index].pads; decks[index] = deck
                            } else { decks.append(deck) }
                            persist(decks, selected: deck.id)
                        }.disabled(saving || store.busy || !store.connected || !validName)
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
