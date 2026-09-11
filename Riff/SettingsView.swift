import SwiftUI
import VisionKit
import AVFoundation

struct ConnectionView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var scanning = false
    @State private var link = ""
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 20) {
                        Image(systemName: "ipad.landscape").font(.system(size: 40, weight: .light))
                        Image(systemName: "link").font(.title2).foregroundStyle(Palette.accent)
                        Image(systemName: "desktopcomputer").font(.system(size: 40, weight: .light))
                    }.frame(maxWidth: .infinity).padding(.vertical, 22)
                    Text(store.connected ? "Connected to your PC" : "Connect your PC").font(.system(size: 32, weight: .semibold, design: .rounded))
                    Text("Open Riff on Windows, then scan its pairing code with your iPad.").foregroundStyle(.secondary)
                    instruction("1", "Open Riff on Windows", "Run Riff.Companion.exe, then leave it open in the system tray.")
                    instruction("2", "Join the same network", "Connect your iPad and PC to the same home network. Allow Riff through Windows Firewall on private networks.")
                    instruction("3", "Scan the code on your PC", "Select your home-network address in the companion, then scan its pairing code. You can also copy and privately transfer the pairing link.")
                    if DataScannerViewController.isSupported {
                        Button {
                            Task {
                                if await AVCaptureDevice.requestAccess(for: .video) { scanning = true }
                                else { failure = "Allow camera access in iPad Settings > Apps > Riff, or paste the pairing link below." }
                            }
                        } label: { Label("Scan pairing code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }.buttonStyle(AccentButtonStyle())
                    }
                    TextField("riff://connect?host=…", text: $link, axis: .vertical)
                        .lineLimit(3...5).textInputAutocapitalization(.never).autocorrectionDisabled().font(.subheadline)
                        .padding(16).background(Palette.raised, in: RoundedRectangle(cornerRadius: 12)).privacySensitive()
                    HStack {
                        PasteButton(payloadType: String.self) { values in if let value = values.first { link = value } }.labelStyle(.titleOnly)
                        Spacer()
                        Button { connect() } label: { Label(store.connecting ? "Connecting…" : "Connect PC", systemImage: "link") }
                            .buttonStyle(AccentButtonStyle()).disabled(link.isEmpty || store.connecting)
                    }
                    if let failure { Text(failure).font(.subheadline).foregroundStyle(.red) }
                    Label("Encrypted and local. Your pairing link is a key to this PC; keep it private.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
                    if store.paired { Button("Forget this PC", role: .destructive) { store.disconnect(); dismiss() } }
                }.padding(30)
            }.background(Palette.background).navigationTitle("Connect your PC").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(store.connecting) } }
        }.interactiveDismissDisabled(store.connecting)
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    PairingScanner(onScan: { value in link = value; scanning = false }, onFailure: { text in failure = text; scanning = false })
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Scan your PC’s code").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } } }
                }
            }
    }
    private func connect() {
        failure = nil
        Task { do { try await store.pair(link); dismiss() } catch { failure = error.localizedDescription } }
    }
    private func instruction(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.subheadline.bold()).foregroundStyle(Palette.accent).frame(width: 30, height: 30).background(Palette.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct SettingsView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var output = ""
    @State private var volume: Float = 0.75
    @State private var saving = false
    @State private var failure: String?
    @State private var connection = false
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Your PC") {
                    LabeledContent("Connection", value: store.connected ? store.snapshot.computerName : "Offline")
                    Button("Pair or change PC", systemImage: "link") { connection = true }
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
                        Button("Play a test sound on PC", systemImage: "play.circle") { Task { await store.preview(clip) } }.disabled(!store.connected || saving)
                    }
                    if let failure { Text(failure).foregroundStyle(.red) }
                } header: { Text("Audio routing") } footer: { Text("Apply changes before testing. New sounds use the selected output. Stop existing sounds before switching devices.") }
                Section("Make sounds your voice") { GameChatInstructions() }
                Section("Layout") {
                    NavigationLink("Grid size") { GridLayoutView() }
                    Toggle("Follow my Steam game", isOn: $store.autoSwitch)
                    Text("Link a game in Deck settings. Riff switches when a new game starts, and pauses switching while you edit. You can always choose another deck manually.").font(.caption).foregroundStyle(.secondary)
                }
                Section { Text("Riff 1.0").foregroundStyle(.secondary) }
            }.scrollContentBackground(.hidden).background(Palette.background)
                .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { output = store.snapshot.outputId; volume = store.snapshot.volume }
                .sheet(isPresented: $connection) { ConnectionView() }
        }
    }
}

struct GameChatInstructions: View {
    var body: some View {
        Group {
                    Label("1. Install a virtual audio cable on Windows.", systemImage: "cable.connector")
                    Label("2. Select CABLE Input in Riff’s Sound output controls.", systemImage: "speaker.wave.2")
                    Label("3. Select CABLE Output as your game or Discord microphone.", systemImage: "mic")
                    Label("4. Use voice activation, or hold your game’s push-to-talk key while the sound plays.", systemImage: "waveform")
                    Text("If a clip is cut off, lower the input threshold and disable noise suppression or automatic voice processing in your chat app. To hear it yourself, use Windows’ Listen to this device option on CABLE Output, with headphones as the playback device.").font(.caption).foregroundStyle(.secondary)
                    Text("This sends prerecorded sounds instead of your physical microphone. To mix your live voice with sounds, use a mixer such as Voicemeeter.").font(.caption).foregroundStyle(.secondary)
                    Link("Get VB-CABLE", destination: URL(string: "https://vb-audio.com/Cable/")!)
        }
    }
}
