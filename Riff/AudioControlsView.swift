import SwiftUI

struct AudioControlsView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var output = ""
    @State private var volume: Float = 0.75
    @State private var saving = false
    @State private var failure: String?
    @State private var connection = false

    var body: some View {
        NavigationStack {
            Form {
                if !store.connected {
                    Section {
                        Text("Connect your PC to choose where sounds play and adjust their volume.").foregroundStyle(.secondary)
                        Button("Connect PC", systemImage: "link") { connection = true }
                    }
                }
                Section {
                    Picker("Output", selection: $output) {
                        if store.snapshot.outputs.isEmpty { Text("Connect your PC first").tag("") }
                        ForEach(store.snapshot.outputs) { Text($0.name).tag($0.id) }
                        if !output.isEmpty && !store.snapshot.outputs.contains(where: { $0.id == output }) { Text("Disconnected output").tag(output) }
                    }
                    VStack(spacing: 12) {
                        HStack { Text("Sound volume"); Spacer(); Text("\(Int(volume * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                        Slider(value: $volume, in: 0...1).accessibilityLabel("Soundboard volume")
                    }.padding(.vertical, 8)
                } footer: {
                    Text("Previews use this output too. Choose speakers or headphones for listening, or your virtual cable for game chat. Stop existing sounds before switching outputs.")
                }.disabled(!store.connected || saving)
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
                Section {
                    NavigationLink {
                        Form { GameChatInstructions() }
                            .scrollContentBackground(.hidden).background(Palette.background)
                            .navigationTitle("Game chat setup").navigationBarTitleDisplayMode(.inline)
                    } label: { Label("Game chat setup", systemImage: "mic") }
                }
            }
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Sound output").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Applying…" : "Apply") {
                        saving = true; failure = nil
                        Task {
                            do { try await store.audio(output: output, volume: volume); dismiss() }
                            catch { failure = error.localizedDescription }
                            saving = false
                        }
                    }.fontWeight(.semibold).disabled(!store.connected || saving)
                }
            }
            .safeAreaInset(edge: .bottom) { SoundPreviewBar() }
            .onAppear { load() }
            .sheet(isPresented: $connection, onDismiss: load) { ConnectionView() }
        }.interactiveDismissDisabled(saving)
    }
    private func load() { output = store.snapshot.outputId; volume = store.snapshot.volume }
}
