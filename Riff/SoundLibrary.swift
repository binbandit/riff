import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(RiffStore.self) private var store
    var onAssign: (Clip) -> Void
    @State private var search = ""
    @State private var importing = false
    @State private var working = false
    @State private var deleteClip: Clip?
    private var clips: [Clip] { store.snapshot.clips.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Find your sound", text: $search) }
                    .padding(13).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                Button { importing = true } label: { Label(working ? "Importing…" : "Import audio", systemImage: "square.and.arrow.down") }
                    .buttonStyle(QuietButtonStyle()).disabled(!store.connected || working)
            }
            Text("\(store.snapshot.clips.count) sounds · Record something yours, or bring a favorite clip.").font(.caption).foregroundStyle(.secondary)
            if clips.isEmpty {
                ContentUnavailableView.search(text: search).frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(clips) { clip in
                            HStack(spacing: 16) {
                                Button { Task { await store.preview(clip) } } label: {
                                    Image(systemName: "play.fill").font(.system(size: 15)).foregroundStyle(Palette.accent)
                                        .frame(width: 46, height: 46).background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityLabel("Preview \(clip.name)")
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(clip.name).font(.system(size: 15, weight: .medium))
                                    Text(String(format: "%.1f seconds", clip.duration)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { onAssign(clip) } label: { Label("Add to deck", systemImage: "plus") }.buttonStyle(QuietButtonStyle()).disabled(!store.connected)
                                Menu {
                                    Button("Delete sound", role: .destructive) { deleteClip = clip }.disabled(!store.connected)
                                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 44).foregroundStyle(.secondary) }.accessibilityLabel("Sound options for \(clip.name)")
                            }.padding(14).background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }.padding(.bottom, 24)
                }.scrollIndicators(.hidden)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.wav, .mp3, .mpeg4Audio, .aiff, .audio]) { result in
            switch result {
            case .success(let url):
                working = true
                Task {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() }; working = false }
                    do {
                        let clip = try await store.upload(url, name: String(url.deletingPathExtension().lastPathComponent.prefix(60)))
                        onAssign(clip)
                    } catch { store.error = error.localizedDescription }
                }
            case .failure(let error): store.error = error.localizedDescription
            }
        }
        .confirmationDialog("Delete \(deleteClip?.name ?? "sound")?", isPresented: Binding(get: { deleteClip != nil }, set: { if !$0 { deleteClip = nil } }), titleVisibility: .visible) {
            Button("Delete sound", role: .destructive) {
                if let clip = deleteClip { Task { await store.deleteClip(clip) } }
                deleteClip = nil
            }
        } message: { Text("Sounds assigned to buttons must be removed from those buttons first.") }
    }
}

struct RecordingView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = SnippetRecorder()
    @State private var name = ""
    @State private var uploading = false
    @State private var failure: String?
    var onRecorded: (Clip) -> Void
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 10)
                eyebrow("TURN A MOMENT INTO A BUTTON")
                Text(recorder.recording ? "You’re on." : recorder.url != nil ? "That’s a keeper." : "Make some noise.")
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-0.8)
                Text(recorder.recording ? "Recording from your iPad microphone" : recorder.url != nil ? "Give your snippet a name, then add it to your deck." : "A catchphrase. A battle cry. An extremely good impression.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(alignment: .center, spacing: 5) {
                    ForEach(0..<37, id: \.self) { index in
                        Capsule().fill(Palette.accent.opacity(recorder.recording ? 0.8 : 0.22))
                            .frame(width: 4, height: recorder.recording ? max(5, CGFloat(recorder.level) * 100 * (0.35 + abs(sin(Double(index) * 1.8)))) : 5)
                    }
                }.frame(height: 100).animation(.linear(duration: 0.08), value: recorder.level).accessibilityHidden(true)
                Text(String(format: "%02d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60))
                    .font(.system(size: 36, weight: .light, design: .monospaced)).monospacedDigit()
                if recorder.url != nil && !recorder.recording {
                    TextField("Name your sound", text: $name).textFieldStyle(.plain).padding(16)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12)).frame(maxWidth: 340)
                    HStack(spacing: 16) {
                        Button { recorder.listen() } label: { Label("Listen", systemImage: "play.fill") }.buttonStyle(QuietButtonStyle())
                        Button { Task { await recorder.start() } } label: { Label("Try again", systemImage: "arrow.counterclockwise") }.buttonStyle(QuietButtonStyle())
                    }
                    Button { upload() } label: { Label(uploading ? "Sending to your PC…" : "Save & make a button", systemImage: "plus.square") }
                        .buttonStyle(AccentButtonStyle()).disabled(uploading || name.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button {
                        if recorder.recording { recorder.stop() } else { Task { await recorder.start() } }
                    } label: {
                        Image(systemName: recorder.recording ? "stop.fill" : "mic.fill").font(.system(size: 28))
                            .foregroundStyle(Palette.background).frame(width: 82, height: 82)
                            .background(Palette.accent, in: Circle()).padding(7).overlay(Circle().stroke(Palette.accent.opacity(0.25), lineWidth: 2))
                    }.buttonStyle(PadPressStyle()).accessibilityLabel(recorder.recording ? "Stop recording" : "Start recording")
                }
                if let text = failure ?? recorder.error { Text(text).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center) }
                Spacer(minLength: 10)
                Label("Up to 60 seconds · Saved to your PC · Always yours", systemImage: "lock").font(.caption).foregroundStyle(.tertiary)
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background)
                .navigationTitle("Record a snippet").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(uploading) } }
        }
        .interactiveDismissDisabled(recorder.recording || uploading)
        .onDisappear { recorder.cleanup() }
        .onChange(of: scenePhase) { _, phase in if phase != .active && recorder.recording { recorder.stop() } }
        .disabled(uploading)
    }
    private func upload() {
        guard let url = recorder.url else { return }
        uploading = true; failure = nil
        Task {
            do {
                let clip = try await store.upload(url, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
                // Present the editor after the recording sheet has finished dismissing.
                Task { try? await Task.sleep(for: .milliseconds(450)); onRecorded(clip) }
            } catch { failure = error.localizedDescription }
            uploading = false
        }
    }
}
