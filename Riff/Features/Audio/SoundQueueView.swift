import SwiftUI

struct SoundQueueView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let contents = store.queueContents
        NavigationStack {
            List {
                if !store.playingPadIDs.isEmpty {
                    Section("Now playing") {
                        ForEach(store.playingPadIDs.sorted(), id: \.self) { id in
                            Label(title(for: id), systemImage: "waveform")
                        }
                    }
                }
                Section {
                    if store.queuedPadIDs.isEmpty {
                        ContentUnavailableView("Queue is empty", systemImage: "text.line.first.and.arrowtriangle.forward",
                                               description: Text("Tap sounds on your deck to add them here while another sound plays."))
                    } else {
                        ForEach(Array(contents.padIDs.enumerated()), id: \.offset) { index, id in
                            HStack(spacing: 12) {
                                Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                                    .frame(minWidth: 24)
                                Text(title(for: id)).frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    Task { await store.removeQueuedSound(at: index, expected: contents) }
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                        .frame(width: 44, height: 44)
                                }.buttonStyle(.borderless)
                                    .accessibilityLabel("Remove \(title(for: id)) from queue")
                                    .disabled(!store.supportsQueueEditing || store.updatingQueue)
                            }
                            .accessibilityAction(named: "Move earlier") {
                                if index > 0 { Task { await store.moveQueuedSound(from: index, to: index - 1, expected: contents) } }
                            }
                            .accessibilityAction(named: "Move later") {
                                if index + 1 < store.queuedPadIDs.count {
                                    Task { await store.moveQueuedSound(from: index, to: index + 1, expected: contents) }
                                }
                            }
                            .moveDisabled(!store.supportsQueueEditing || store.updatingQueue)
                        }
                        .onMove { source, destination in
                            guard let index = source.first else { return }
                            let target = destination > index ? destination - 1 : destination
                            Task { await store.moveQueuedSound(from: index, to: target, expected: contents) }
                        }
                    }
                } header: {
                    Text("Up next · \(store.queuedPadIDs.count)")
                } footer: {
                    Text(store.supportsQueueEditing
                         ? "Drag the handles to change the order. Clearing the queue keeps the current sound playing."
                         : "Update Riff on your PC to clear and reorder the queue. You can still tap a waiting sound on your deck to remove it.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Sound queue").navigationBarTitleDisplayMode(.inline)
            .alert("Could not update queue", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clear queue", role: .destructive) { Task { await store.clearQueue() } }
                        .disabled(store.queuedPadIDs.isEmpty || !store.supportsQueueEditing || store.updatingQueue)
                }
            }
            .task {
                while !Task.isCancelled {
                    await store.refreshPlayback()
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                }
            }
        }
    }

    private func title(for id: String) -> String {
        store.snapshot.decks.lazy.flatMap(\.pads).first { $0.id == id }?.title ?? "Sound"
    }
}
