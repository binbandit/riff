import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(RiffStore.self) private var store
    var onAssign: (Clip) -> Void
    @State private var search = ""
    @State private var importing = false
    @State private var recording = false
    @State private var working = false
    @State private var deleteClip: Clip?
    @State private var recorded: Clip?
    private var clips: [Clip] { store.snapshot.clips.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            if !store.connected {
                Section { Text("Preview sounds here. Connect your PC to record, import, or add them to a deck.").font(.subheadline).foregroundStyle(.secondary) }
            }
            Section {
                ForEach(clips) { clip in
                    HStack(spacing: 14) {
                        Button { Task { await store.preview(clip) } } label: {
                            Image(systemName: "play.fill").font(.body).foregroundStyle(Palette.accent)
                                .frame(width: 48, height: 48).background(Palette.accent.opacity(0.09), in: Circle())
                        }.buttonStyle(.borderless).accessibilityLabel("Play \(clip.name)")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(clip.name).font(.body.weight(.medium))
                            Text(String(format: "%.1f sec", clip.duration)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { onAssign(clip) } label: { Image(systemName: "plus.circle.fill").font(.title2).padding(8) }
                            .buttonStyle(.borderless).disabled(!store.connected).accessibilityLabel("Add \(clip.name) to deck")
                    }.padding(.vertical, 6)
                        .swipeActions { Button("Delete", role: .destructive) { deleteClip = clip }.disabled(!store.connected) }
                        .contextMenu { Button("Delete sound", role: .destructive) { deleteClip = clip }.disabled(!store.connected) }
                }
            } header: { Text("\(store.snapshot.clips.count) sounds") }
            if working { HStack { ProgressView(); Text("Importing sound…") } }
        }
        .scrollContentBackground(.hidden).background(Palette.background)
        .searchable(text: $search, prompt: "Find a sound")
        .overlay { if clips.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) } }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Record sound", systemImage: "mic") { recording = true }
                    Button("Import audio", systemImage: "folder") { importing = true }
                } label: { Image(systemName: "plus") }.disabled(!store.connected || working).accessibilityLabel("Add sound")
            }
        }
        .sheet(isPresented: $recording, onDismiss: { if let recorded { self.recorded = nil; onAssign(recorded) } }) {
            RecordingView { clip in recorded = clip; recording = false }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.wav, .mp3, .mpeg4Audio, .aiff, UTType(filenameExtension: "aac") ?? .audio]) { result in
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
                if let clip = deleteClip { Task { await store.deleteClip(clip) } }; deleteClip = nil
            }
        } message: { Text("Remove this sound from any buttons before deleting it.") }
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
            ScrollView {
                VStack(spacing: 28) {
                    Text(recorder.url != nil && !recorder.recording ? "Your new sound" : "Record a sound")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .padding(.top, 30)
                    Text(recorder.recording ? "Recording from your iPad" : recorder.url != nil ? "Listen back and give it a name." : "Tap the red button when you’re ready.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack(spacing: 5) {
                        ForEach(0..<43, id: \.self) { index in
                            Capsule().fill(recorder.recording ? Palette.accent : Palette.accent.opacity(0.25))
                                .frame(width: 4, height: recorder.recording ? max(5, CGFloat(recorder.level) * 100 * (0.35 + abs(sin(Double(index) * 1.8)))) : 5)
                        }
                    }.frame(height: 120).animation(.linear(duration: 0.08), value: recorder.level).accessibilityHidden(true)
                    Text(String(format: "%02d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60))
                        .font(.system(size: 56, weight: .light, design: .rounded)).monospacedDigit()
                    if recorder.url != nil && !recorder.recording {
                        TextField("Sound name", text: $name).font(.title3).multilineTextAlignment(.center)
                            .padding(18).background(Palette.panel, in: RoundedRectangle(cornerRadius: 16)).frame(maxWidth: 360)
                        HStack(spacing: 12) {
                            Button { recorder.listen() } label: { Label("Listen", systemImage: "play.fill") }.buttonStyle(QuietButtonStyle())
                            Button { Task { await recorder.start() } } label: { Label("Retake", systemImage: "arrow.counterclockwise") }.buttonStyle(QuietButtonStyle())
                        }
                        Button { upload() } label: { Text(uploading ? "Saving…" : "Save & add button") }.buttonStyle(AccentButtonStyle())
                            .disabled(uploading || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button {
                            if recorder.recording { recorder.stop() } else { Task { await recorder.start() } }
                        } label: {
                            ZStack {
                                Circle().strokeBorder(Palette.accent.opacity(0.22), lineWidth: 3).frame(width: 96, height: 96)
                                if recorder.recording { RoundedRectangle(cornerRadius: 8).fill(Palette.accent).frame(width: 38, height: 38) }
                                else { Circle().fill(Palette.accent).frame(width: 76, height: 76) }
                            }
                        }.buttonStyle(PadPressStyle()).accessibilityLabel(recorder.recording ? "Stop recording" : "Start recording")
                        Text("Up to 60 seconds").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let text = failure ?? recorder.error { Text(text).font(.subheadline).foregroundStyle(.red).multilineTextAlignment(.center) }
                }.padding(28).frame(maxWidth: .infinity)
            }.background(Palette.background)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(uploading) } }
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
                onRecorded(clip)
            } catch { failure = error.localizedDescription }
            uploading = false
        }
    }
}
