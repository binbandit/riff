import SwiftUI

struct AudioControlsView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var output = ""
    @State private var volume: Float = 0.75
    @State private var monitorEnabled = false
    @State private var monitorOutput = ""
    @State private var monitorVolume: Float = 0.75
    @State private var saving = false
    @State private var failure: String?
    @State private var connection = false
    @State private var hasLoadedAudio = false
    @State private var hasLoadedConnectedAudio = false
    @State private var queue = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Playback", selection: Binding(get: { store.effectiveSoundMode }, set: { store.soundMode = $0 })) {
                        ForEach(store.availablePlaybackModes) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                        .disabled(store.connected && !store.supportsPlayback)
                } header: { Text("When you tap a sound") } footer: {
                    if store.connected && !store.supportsPlayback {
                        Text("Update Riff on your PC to use these playback controls.")
                    } else {
                        Text(store.effectiveSoundMode.explanation + " This choice is saved automatically. Switching to another mode clears waiting sounds on your next tap.")
                        if store.connected && !store.supportsQueue {
                            Text("Update Riff on your PC to add Queue mode.")
                        }
                    }
                }
                if store.effectiveSoundMode == .queue || !store.queuedPadIDs.isEmpty {
                    Section {
                        Button { queue = true } label: {
                            HStack {
                                Label("Sound queue", systemImage: "list.bullet")
                                Spacer()
                                Text("\(store.queuedPadIDs.count) waiting").foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
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
                    if store.supportsMonitoring {
                        HeadphoneControls(enabled: $monitorEnabled, output: $monitorOutput, volume: $monitorVolume, outputs: store.snapshot.outputs)
                    } else if store.connected {
                        Text("Update Riff on your PC to hear sounds through your headphones while sending them to chat.").font(.caption).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Deck buttons and PC test sounds use this output. Library previews play on your iPad at its device volume. Use Stop all before changing outputs or Hear sounds myself.")
                }.disabled(!store.connected || saving)
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
                Section {
                    NavigationLink {
                        AudioSetupView()
                    } label: { Label("Microphone, sounds & music", systemImage: "mic") }
                }
            }
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Sound controls").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Applying…" : "Apply") {
                        saving = true; failure = nil
                        Task {
                            do { try await store.audio(output: output, volume: volume, monitorEnabled: monitorEnabled, monitorOutput: monitorOutput, monitorVolume: monitorVolume); dismiss() }
                            catch { failure = error.localizedDescription }
                            saving = false
                        }
                    }.fontWeight(.semibold).disabled(!store.connected || saving)
                }
            }
            .safeAreaInset(edge: .bottom) { SoundPreviewBar() }
            .onAppear { if !hasLoadedAudio { load() } }
            .onChange(of: store.connected) { _, connected in
                if connected && !hasLoadedConnectedAudio { load() }
            }
            .sheet(isPresented: $connection) { ConnectionView(onConnectionChanged: load) }
            .sheet(isPresented: $queue) { SoundQueueView() }
        }.interactiveDismissDisabled(saving)
    }
    private func load() {
        output = store.snapshot.outputId; volume = store.snapshot.volume
        monitorEnabled = store.snapshot.monitorEnabled ?? false
        monitorOutput = store.snapshot.monitorOutputId ?? ""
        monitorVolume = store.snapshot.monitorVolume ?? 0.75
        hasLoadedAudio = true; hasLoadedConnectedAudio = store.connected
    }
}

struct HeadphoneControls: View {
    @Binding var enabled: Bool
    @Binding var output: String
    @Binding var volume: Float
    let outputs: [AudioOutput]

    var body: some View {
        Toggle("Hear sounds myself", systemImage: "headphones", isOn: $enabled)
        if enabled {
            Picker("Headphones", selection: $output) {
                ForEach(outputs) { Text($0.name).tag($0.id) }
                if !output.isEmpty && !outputs.contains(where: { $0.id == output }) {
                    Text("Disconnected headphones").tag(output)
                }
            }
            VStack(spacing: 12) {
                HStack { Text("Headphone volume"); Spacer(); Text("\(Int(volume * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: $volume, in: 0...1).accessibilityLabel("Headphone volume")
            }.padding(.vertical, 8)
            Text("Choose headphones connected to your PC. This volume only changes what you hear. If Windows or your mixer already plays the clips through your headphones, use just one monitoring route to avoid an echo.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
