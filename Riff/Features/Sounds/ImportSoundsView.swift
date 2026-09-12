import SwiftUI

struct SoundImportRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ImportSoundsView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var batch: SoundBatchImport
    let onAddToDeck: ([Clip]) -> Void

    init(urls: [URL], onAddToDeck: @escaping ([Clip]) -> Void) {
        _batch = State(initialValue: SoundBatchImport(urls: urls))
        self.onAddToDeck = onAddToDeck
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Save all selected files using their filenames. Each sound can be up to 60 seconds long. Longer files can be imported individually to trim them.")
                        .foregroundStyle(.secondary)
                    if batch.running {
                        ProgressView(value: Double(batch.completedCount), total: Double(max(1, batch.items.count))) {
                            Text("Importing \(batch.completedCount + 1) of \(batch.items.count)…")
                        }
                    } else if batch.finished {
                        Text("\(batch.imported.count) imported · \(batch.items.count - batch.imported.count) couldn’t be imported")
                            .fontWeight(.medium)
                    }
                }
                Section("\(batch.items.count) sounds") {
                    ForEach(batch.items) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(SoundBatchImport.soundName(for: item.url))
                                if let failure = item.failure {
                                    Text(failure).font(.caption).foregroundStyle(.red)
                                }
                            }
                            Spacer()
                            if item.clip != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent).accessibilityLabel("Imported")
                            } else if batch.currentID == item.id {
                                ProgressView().accessibilityLabel("Importing")
                            } else if item.failure != nil {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                if batch.finished && !batch.imported.isEmpty {
                    Section {
                        if batch.imported.count <= 48 {
                            Button("Add \(batch.imported.count) to deck", systemImage: "plus.square.on.square") {
                                onAddToDeck(batch.imported); dismiss()
                            }
                        } else {
                            Text("Your sounds are in the library. Use Quick add to choose up to 48 sounds for each deck.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !store.connected {
                    Text("Connect your PC to import sounds.").foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Import sounds").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(batch.finished ? "Done" : "Cancel") { dismiss() }.disabled(batch.running)
                }
                if !batch.finished {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import all") {
                            Task { await batch.run { url, name in try await store.upload(url, name: name) } }
                        }.fontWeight(.semibold).disabled(batch.running || !store.connected || store.busy)
                    }
                }
            }
        }.interactiveDismissDisabled(batch.running)
    }
}
