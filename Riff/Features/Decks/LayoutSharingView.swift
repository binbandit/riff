import SwiftUI
import UniformTypeIdentifiers

nonisolated struct LayoutFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct LayoutSharingView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let sourceDeck: Deck
    var button: Pad? = nil
    @State private var exportFile: LayoutFile?
    @State private var exporting = false
    @State private var importing = false
    @State private var loading = false
    private struct Review: Identifiable { let id = UUID(); let package: DeckPackage }
    @State private var review: Review?
    @State private var failure: String?
    private var deck: Deck { store.snapshot.decks.first { $0.id == sourceDeck.id } ?? sourceDeck }
    private var filename: String {
        (button?.title ?? deck.name).components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-") + ".riff.json"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(button?.title ?? deck.name, systemImage: button == nil ? deck.icon : "square.dashed")
                        .font(.title3.weight(.semibold)).padding(.vertical, 8)
                    LabeledContent("Includes", value: button == nil ? "\(deck.pads.count) buttons and grid size" : "One button and its actions")
                    Button(button == nil ? "Export deck…" : "Export button…", systemImage: "square.and.arrow.up") { prepareExport() }
                } header: { Text("Share a layout") } footer: {
                    Text("The file includes button names, icons, colors, pins, text, websites, shortcuts, and sequences. Audio files, PC settings, and app permissions aren't included. Match sounds and apps when importing on another PC.")
                }
                Section {
                    Button("Choose a Riff layout…", systemImage: "square.and.arrow.down") { failure = nil; importing = true }
                    if loading { HStack { ProgressView(); Text("Opening layout…") } }
                } header: { Text("Import a deck or button") } footer: {
                    Text("Open a .riff.json file exported by Riff. Review its actions and match resources before adding it as a new deck or to an existing deck. Elgato .streamDeckProfile files aren't supported.")
                }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
            }
            .disabled(loading)
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Share & import").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(loading) } }
        }
#if DEBUG
        .task {
            if DesignPreview.screen == "layout-import" {
                do {
                    review = Review(package: try DeckPackage.make(deck: deck, snapshot: store.snapshot, grid: store.grid))
                } catch { failure = error.localizedDescription }
            } else if DesignPreview.screen == "layout-export" { prepareExport() }
        }
#endif
        .interactiveDismissDisabled(loading)
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .json, defaultFilename: filename) { result in
            switch result {
            case .success: store.message("Layout exported")
            case .failure(let error): failure = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): failure = error.localizedDescription
            }
        }
        .sheet(item: $review) { review in
            if #available(iOS 18.0, *) { LayoutImportView(package: review.package, onImported: { dismiss() }).presentationSizing(.page) }
            else { LayoutImportView(package: review.package, onImported: { dismiss() }) }
        }
    }

    private func prepareExport() {
        do {
            let package = try DeckPackage.make(deck: deck, snapshot: store.snapshot, grid: store.grid, button: button)
            exportFile = LayoutFile(data: try package.encoded()); failure = nil; exporting = true
        } catch { failure = error.localizedDescription }
    }
    private func load(_ url: URL) {
        loading = true
        let limit = DeckPackage.maximumBytes
        Task {
            defer { loading = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit {
                        throw CocoaError(.fileReadTooLarge)
                    }
                    return try Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                review = Review(package: try DeckPackage.read(data))
            } catch { failure = error.localizedDescription }
        }
    }
}

struct LayoutImportView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let package: DeckPackage
    var onImported: () -> Void = {}
    @State private var name = ""
    @State private var targetID = ""
    @State private var matches: [String: String] = [:]
    @State private var saving = false
    @State private var loaded = false
    @State private var newDeckID = UUID().uuidString
    @State private var buttonIDs: [String: String] = [:]
    @State private var failure: String?
    private var missing: Int { package.missingMatches(matches, in: store.snapshot).count }
    private var compatibilityIssue: String? { store.connected ? package.compatibilityIssue(in: store.snapshot) : nil }
    private var hasRoom: Bool {
        targetID.isEmpty ? store.snapshot.decks.count < 20 : store.snapshot.decks.contains { $0.id == targetID && $0.pads.count + package.deck.pads.count <= 48 }
    }
    private var validName: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 40 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Add to", selection: $targetID) {
                        Text("New deck").tag("")
                        ForEach(store.snapshot.decks) { deck in Text("\(deck.name) · \(deck.pads.count)/48").tag(deck.id) }
                    }
                    if targetID.isEmpty {
                        TextField("Deck name", text: $name)
                        if !validName { Text("Use a deck name of 1–40 characters.").font(.caption).foregroundStyle(.red) }
                        Text("The exported grid size will be applied to the new deck on this iPad.").font(.caption).foregroundStyle(.secondary)
                    }
                    if !hasRoom { Text("Choose a deck with enough room. Riff supports 20 decks and 48 buttons per deck.").font(.caption).foregroundStyle(.red) }
                } header: { Text("\(package.deck.pads.count) buttons from \(package.deck.name)") }
                if !package.dependencies.isEmpty {
                    Section {
                        ForEach(package.dependencies) { dependency in
                            Picker(selection: Binding(get: { matches[dependency.id] ?? "" }, set: { matches[dependency.id] = $0 })) {
                                Text("Choose a match").tag("")
                                ForEach(dependency.options(in: store.snapshot), id: \.id) { item in Text(item.name).tag(item.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(dependency.name)
                                    Text(dependency.label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: { Text(missing == 0 ? "Resources matched" : "Match resources · \(missing) remaining") } footer: {
                        Text("Choose sounds from your library, applications approved on Windows, and linked decks. If an item is missing, cancel and add it first. Both sides of an action switch use these matches.")
                    }
                }
                Section {
                    ForEach(package.deck.pads) { pad in
                        DisclosureGroup {
                            if ActionKind(rawValue: pad.kind)?.isSequence == true {
                                if pad.kind == "switch" { Text("First press").font(.subheadline.weight(.semibold)) }
                                actionRows(pad.steps)
                                if pad.kind == "switch" {
                                    Text("Second press").font(.subheadline.weight(.semibold))
                                    actionRows(pad.alternateSteps ?? [])
                                }
                            } else { actionRow(kind: pad.kind, value: pad.value) }
                            if let action = pad.doubleTapAction {
                                Text("Double-tap").font(.subheadline.weight(.semibold))
                                actionRow(kind: action.kind, value: action.value)
                            }
                            if let action = pad.holdAction {
                                Text("Hold").font(.subheadline.weight(.semibold))
                                actionRow(kind: action.kind, value: action.value)
                            }
                        } label: {
                            HStack {
                                PadGlyph(icon: pad.icon, size: 24).foregroundStyle(pad.tint).frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pad.title)
                                    Text(pad.typeName).font(.caption).foregroundStyle(.secondary)
                                }
                                if pad.isPinned { Image(systemName: "pin.fill").font(.caption).accessibilityLabel("Pinned") }
                            }
                        }
                    }
                } header: { Text("Review actions") } footer: {
                    Text("Buttons are added as new copies. Application and Steam profile links are left for you to configure in Deck settings.")
                }
                if let compatibilityIssue { Section { Text(compatibilityIssue).foregroundStyle(.red) } }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Import layout").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Importing…" : "Import") { importLayout() }
                        .disabled(saving || store.busy || !hasRoom || !validName || missing > 0 || compatibilityIssue != nil)
                }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                name = package.deck.name
                buttonIDs = Dictionary(uniqueKeysWithValues: package.deck.pads.map { ($0.id, UUID().uuidString) })
                if package.content == "button" { targetID = store.selectedDeckId }
                matches = package.suggestedMatches(in: store.snapshot)
            }
        }.interactiveDismissDisabled(saving)
    }

    private func actionRows(_ steps: [ActionStep]) -> some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            VStack(alignment: .leading, spacing: 3) {
                Text("\(index + 1). \(ActionKind(rawValue: step.kind)?.label ?? step.kind) · wait \(step.delayMs) ms")
                    .font(.caption).foregroundStyle(.secondary)
                Text(package.actionDescription(kind: step.kind, value: step.value)).textSelection(.enabled)
            }.padding(.vertical, 4)
        }
    }
    private func actionRow(kind: String, value: String) -> some View {
        Text(package.actionDescription(kind: kind, value: value).isEmpty ? (ActionKind(rawValue: kind)?.label ?? kind) : package.actionDescription(kind: kind, value: value))
            .textSelection(.enabled)
    }
    private var completedImportID: String? {
        let id = targetID.isEmpty ? newDeckID : targetID
        let ids = Set(buttonIDs.values)
        guard let deck = store.snapshot.decks.first(where: { $0.id == id }),
              (targetID.isEmpty || !ids.isEmpty), ids.isSubset(of: Set(deck.pads.map(\.id))) else { return nil }
        return id
    }
    private func finishImport(_ id: String) {
        store.selectedDeckId = id
        if targetID.isEmpty { store.grid = package.grid }
        store.message("Imported \(package.deck.pads.count) buttons")
        dismiss(); onImported()
    }
    private func importLayout() {
        saving = true; failure = nil
        Task {
            defer { saving = false }
            do {
                if let id = completedImportID { finishImport(id); return }
                let deck = try package.importedDeck(name: name, into: targetID.isEmpty ? nil : targetID, matches: matches, snapshot: store.snapshot, newDeckID: newDeckID, buttonIDs: buttonIDs, checkCompatibility: store.connected)
                var decks = store.snapshot.decks
                if let index = decks.firstIndex(where: { $0.id == deck.id }) { decks[index] = deck }
                else { decks.append(deck) }
                try await store.saveDecks(decks)
                finishImport(deck.id)
            } catch {
                // A lost save response may still have committed. Reuse the same IDs on
                // retries and recognize the refreshed result instead of adding copies.
                if let id = completedImportID { finishImport(id) }
                else { failure = error.localizedDescription }
            }
        }
    }
}
