import SwiftUI
import VisionKit
import AVFoundation

struct ConnectionView: View {
    var onConnectionChanged: () -> Void = {}
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
                    if store.paired { Button("Forget this PC", role: .destructive) { store.disconnect(); onConnectionChanged(); dismiss() } }
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
        Task { do { try await store.pair(link); onConnectionChanged(); dismiss() } catch { failure = error.localizedDescription } }
    }
    private func instruction(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.subheadline.bold()).foregroundStyle(Palette.accent).frame(width: 30, height: 30).background(Palette.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
