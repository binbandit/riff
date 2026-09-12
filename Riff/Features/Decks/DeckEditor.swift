import SwiftUI

struct DeckEditor: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var deck: Deck
    @State private var failure: String?
    @State private var saving = false
    @State private var saveStatus = ""
    @State private var confirmDelete = false
    @State private var useAI = true
    @State private var intent = ""
    @State private var nameEdited = false
    @State private var iconEdited = false
    @State private var suggesting = false
    @State private var suggestion: DeckSuggestion?
    @State private var suggestionContext: DeckSuggestionRequest?
    @State private var selectedSuggestions = Set<String>()
    @State private var suggestionError: String?
    @State private var retry = 0
    @State private var suggestionRun = UUID()
    private var isNew: Bool { !store.snapshot.decks.contains { $0.id == deck.id } }
    private var context: DeckSuggestionRequest {
        DeckSuggestionRequest(gameId: deck.steamAppId, appId: deck.linkedAppId ?? "", name: nameEdited ? cleanName : "", intent: intent.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private var request: DeckSuggestionRequest? {
        guard isNew, useAI, !saving, store.padSuggestionsEnabled, context.hasContext,
              context.intent.utf16.count <= 500, context.name.utf16.count <= 40,
              context.gameId.count <= 12, context.gameId.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return context
    }
    private var selectedButtons: [DeckSuggestedButton] {
        guard useAI, suggestionContext == context else { return [] }
        return suggestion?.buttons.filter { selectedSuggestions.contains($0.id) } ?? []
    }
    private struct SuggestionTask: Hashable { let request: DeckSuggestionRequest?; let retry: Int }
    private var cleanName: String { deck.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validName: Bool { !cleanName.isEmpty && cleanName.utf16.count <= 40 }
    var body: some View {
        NavigationStack {
            Form {
                Section("Your deck") {
                    TextField("Deck name", text: Binding(get: { deck.name }, set: { nameEdited = true; deck.name = $0 }))
                    if cleanName.utf16.count > 40 { Text("Use 40 characters or fewer.").font(.caption).foregroundStyle(.red) }
                    Picker("Icon", selection: Binding(get: { deck.icon }, set: { iconEdited = true; deck.icon = $0 })) {
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
                    Text("Games found on your PC stay available here, even offline. With automatic switching enabled in Settings, this deck opens when Steam reports the game running. If multiple games run at once, choose a deck manually.")
                }
                if store.supportsSmartProfiles {
                    Section {
                        Picker("Linked application", selection: Binding(get: { deck.linkedAppId ?? "" }, set: { deck.linkedAppId = $0.isEmpty ? nil : $0 })) {
                            Text("None").tag("")
                            ForEach(store.snapshot.apps) { Text($0.name).tag($0.id) }
                        }
                    } header: { Text("Follow your app") } footer: {
                        Text("Applications allowed on Windows stay available here while offline. Link one to this deck and enable Follow my focused app in Settings. The focused app takes priority over a running Steam game. Each app can be linked to one deck.")
                    }
                }
                if isNew { starterSuggestions }
                if saving && !saveStatus.isEmpty { Section { ProgressView(saveStatus).font(.subheadline) } }
                if let failure { Text(failure).foregroundStyle(.red) }
                if store.snapshot.decks.contains(where: { $0.id == deck.id }) {
                    Section {
                        Button("Duplicate deck", systemImage: "square.on.square") {
                            var source = deck
                            source.pads = store.snapshot.decks.first(where: { $0.id == deck.id })?.pads ?? deck.pads
                            let duplicate = source.duplicated()
                            persist(store.snapshot.decks + [duplicate], selected: duplicate.id)
                        }.disabled(!validName || store.snapshot.decks.count >= 20)
                        Button("Delete deck", role: .destructive) { confirmDelete = true }.disabled(store.snapshot.decks.count <= 1)
                    }
                }
            }.disabled(saving).scrollContentBackground(.hidden).background(Palette.background)
                .navigationTitle(isNew ? "New deck" : "Deck settings").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : isNew ? (selectedButtons.isEmpty ? "Create empty deck" : "Create deck") : "Save") {
                            deck.name = cleanName
                            if isNew { create(); return }
                            var decks = store.snapshot.decks
                            if let index = decks.firstIndex(where: { $0.id == deck.id }) {
                                // Keep current pads when saving deck metadata after another edit.
                                deck.pads = decks[index].pads; decks[index] = deck
                            } else { decks.append(deck) }
                            persist(decks, selected: deck.id)
                        }.disabled(saving || store.busy || !validName)
                    }
                }
                .task(id: SuggestionTask(request: request, retry: retry)) { await suggestStarter() }
                .confirmationDialog("Delete this deck and its buttons? Your sounds stay in the library.", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete deck", role: .destructive) { persist(store.snapshot.decks.filter { $0.id != deck.id }, selected: nil) }
                }
        }.interactiveDismissDisabled(saving)
    }
    @ViewBuilder private var starterSuggestions: some View {
        Section {
            if store.padSuggestionsEnabled {
                Toggle("Suggest starter buttons", isOn: $useAI)
                if useAI {
                    TextField("What do you want this space for?", text: $intent, axis: .vertical)
                        .lineLimit(2...4)
                    if intent.utf16.count > 500 { Text("Use 500 characters or fewer.").font(.caption).foregroundStyle(.red) }
                    if suggesting {
                        HStack(spacing: 10) { ProgressView(); Text("Choosing sounds and buttons…").foregroundStyle(.secondary) }
                    } else if let suggestionError {
                        Text(suggestionError).font(.caption).foregroundStyle(.secondary)
                        Button("Try again", systemImage: "arrow.clockwise") { retry += 1 }
                    } else if suggestion == nil {
                        Text("Choose a game, link an app, or describe your space. AI will suggest a starter set you can review.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("AI starter suggestions", systemImage: "sparkles")
                AISetupLink()
            }
        } header: { Text("Start with AI") } footer: {
            if store.padSuggestionsEnabled && useAI {
                Text("Uses your game, app, description, and sound and button names. Suggestions come from your library, bundled packs, and existing controls. Nothing runs automatically.")
            }
        }
        if useAI, suggestionContext == context, let suggestion {
            Section {
                Text(suggestion.summary).font(.subheadline).foregroundStyle(.secondary)
                ForEach(suggestion.buttons) { button in
                    Toggle(isOn: Binding(get: { selectedSuggestions.contains(button.id) }, set: { selected in
                        if selected { selectedSuggestions.insert(button.id) } else { selectedSuggestions.remove(button.id) }
                    })) {
                        HStack(spacing: 12) {
                            Image(systemName: button.pad.icon).font(.title3).foregroundStyle(Palette.ink)
                                .frame(width: 42, height: 42).background(button.pad.tint, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(button.pad.title).font(.subheadline.weight(.semibold))
                                Text(button.description).font(.caption).foregroundStyle(.secondary)
                                Text(button.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }.tint(Palette.accent)
                }
                Button("Suggest another set", systemImage: "arrow.clockwise") { retry += 1 }
            } header: { Text("\(selectedButtons.count) starter buttons selected") } footer: {
                Text("Deselect anything you don't want. All included sounds are already in your library. You can edit and rearrange every button afterwards.")
            }
        }
    }
    private func suggestStarter() async {
        guard !saving else { return }
        let run = UUID(); suggestionRun = run
        suggesting = false; suggestionError = nil; suggestion = nil; suggestionContext = nil; selectedSuggestions = []
        guard let request else { return }
        suggesting = true
        defer { if suggestionRun == run { suggesting = false } }
        do {
            try await Task.sleep(for: .milliseconds(800))
            let result = try await store.suggestDeck(request)
            guard !Task.isCancelled, suggestionRun == run, self.request == request else { return }
            suggestion = result; suggestionContext = request; selectedSuggestions = Set(result.buttons.map(\.id))
            if !nameEdited { deck.name = result.name }
            if !iconEdited { deck.icon = result.icon }
        } catch {
            guard !Task.isCancelled, suggestionRun == run, self.request == request, !(error is CancellationError) else { return }
            suggestionError = error.localizedDescription
        }
    }
    private func create() {
        let buttons = selectedButtons
        saving = true; failure = nil; saveStatus = "Preparing your deck…"
        Task {
            do { try await store.createSuggestedDeck(deck, buttons: buttons, progress: { saveStatus = $0 }); dismiss() }
            catch { failure = error.localizedDescription }
            saving = false
        }
    }
    private func persist(_ decks: [Deck], selected: String?) {
        saving = true
        Task { do { try await store.saveDecks(decks); if let selected { store.selectedDeckId = selected }; dismiss() } catch { failure = error.localizedDescription }; saving = false }
    }
}
