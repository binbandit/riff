import SwiftUI

struct SettingsView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var output = ""
    @State private var volume: Float = 0.75
    @State private var saving = false
    @State private var failure: String?
    @State private var connection = false
    @State private var hasLoadedAudio = false
    @State private var hasLoadedConnectedAudio = false
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Your PC") {
                    LabeledContent("Connection", value: store.connected ? store.snapshot.computerName : "Offline")
                    Button("Pair or change PC", systemImage: "link") { connection = true }.disabled(saving)
                    NavigationLink { CompanionUpdatesView() } label: {
                        Label(store.updates.release?.isNewer(than: store.snapshot.companionVersion) == true ? "Companion update available" : "Companion updates", systemImage: "arrow.down.circle")
                    }
                }
                Section {
                    Picker("Play sounds through", selection: $output) {
                        if store.snapshot.outputs.isEmpty { Text("Connect your PC first").tag("") }
                        ForEach(store.snapshot.outputs) { Text($0.name).tag($0.id) }
                        if !output.isEmpty && !store.snapshot.outputs.contains(where: { $0.id == output }) { Text("Disconnected output").tag(output) }
                    }
                    HStack { Image(systemName: "speaker.fill"); Slider(value: $volume, in: 0...1); Text("\(Int(volume * 100))%").monospacedDigit().frame(width: 45) }
                    Button(saving ? "Applying…" : "Apply audio settings") {
                        saving = true; failure = nil
                        Task { do { try await store.audio(output: output, volume: volume); store.message("Audio settings saved") } catch { failure = error.localizedDescription }; saving = false }
                    }.disabled(!store.connected || saving)
                    if let clip = store.snapshot.clips.first {
                        Button("Play a test sound on PC", systemImage: "play.circle") { Task { await store.testSoundOnPC(clip) } }.disabled(!store.connected || saving)
                    }
                    if let failure { Text(failure).foregroundStyle(.red) }
                } header: { Text("Audio routing") } footer: { Text("Apply changes before testing. New sounds use the selected output. Stop existing sounds before switching devices.") }
                    .disabled(!store.connected || saving)
                Section {
                    NavigationLink { AudioSetupView() } label: {
                        Label("Microphone, sounds & music", systemImage: "mic")
                    }
                }
                Section("Make it yours") {
                    NavigationLink { AppearanceView() } label: {
                        Label("Appearance", systemImage: "paintpalette")
                    }
                }
                Section("Layout") {
                    NavigationLink("Grid size") { GridLayoutView() }
                    Toggle("Follow my Steam game", isOn: $store.autoSwitch)
                    Text("Link a game in Deck settings. Riff switches when a new game starts, and pauses switching while you edit. You can always choose another deck manually.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("Open-source licenses") {
                        ScrollView {
                            Text((Bundle.main.url(forResource: "MarkdownLicenses", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "Licenses could not be loaded.")
                                .font(.footnote).textSelection(.enabled).padding(24)
                        }.navigationTitle("Open-source licenses").navigationBarTitleDisplayMode(.inline)
                    }
                }
                Section { Text("Riff \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").foregroundStyle(.secondary) }
            }.scrollContentBackground(.hidden).background(Palette.background)
                .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(saving) } }
                .onAppear { if !hasLoadedAudio { loadAudio() } }
                .onChange(of: store.connected) { _, connected in
                    if connected && !hasLoadedConnectedAudio { loadAudio() }
                }
                .sheet(isPresented: $connection) { ConnectionView(onConnectionChanged: loadAudio) }
#if DEBUG
                .navigationDestination(isPresented: .constant(DesignPreview.screen == "appearance")) { AppearanceView() }
#endif
        }.interactiveDismissDisabled(saving)
    }
    private func loadAudio() {
        output = store.snapshot.outputId; volume = store.snapshot.volume
        hasLoadedAudio = true; hasLoadedConnectedAudio = store.connected
    }
}
