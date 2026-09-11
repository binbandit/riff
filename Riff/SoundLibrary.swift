import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(RiffStore.self) private var store
    var onAssign: (Clip) -> Void
    @State private var search = ""
    @State private var importing = false
    @State private var recording = false
    @State private var naming: SoundNameTarget?
    @State private var failure: String?
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
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) { deleteClip = clip }.disabled(!store.connected)
                            Button("Rename") { naming = .existing(clip) }.tint(Palette.accent).disabled(!store.connected)
                        }
                        .contextMenu {
                            Button("Rename sound", systemImage: "pencil") { naming = .existing(clip) }.disabled(!store.connected)
                            Button("Delete sound", role: .destructive) { deleteClip = clip }.disabled(!store.connected)
                        }
                }
            } header: { Text("\(store.snapshot.clips.count) sounds") }

        }
        .scrollContentBackground(.hidden).background(Palette.background)
        .searchable(text: $search, prompt: "Find a sound")
#if DEBUG
        .task {
            if DesignPreview.screen == "rename", let clip = store.snapshot.clips.first { naming = .existing(clip) }
            if DesignPreview.screen == "import", let url = Bundle.main.url(forResource: "level-up", withExtension: "wav") { naming = .imported(url) }
        }
#endif
        .overlay { if clips.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) } }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Record sound", systemImage: "mic") { recording = true }
                    Button("Import audio", systemImage: "folder") { importing = true }
                } label: { Image(systemName: "plus") }.disabled(!store.connected).accessibilityLabel("Add sound")
            }
        }
        .sheet(isPresented: $recording, onDismiss: { if let recorded { self.recorded = nil; onAssign(recorded) } }) {
            RecordingView { clip in recorded = clip; recording = false }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.wav, .mp3, .mpeg4Audio, .aiff, UTType(filenameExtension: "aac") ?? .audio]) { result in
            switch result {
            case .success(let url): naming = .imported(url)
            case .failure(let error): failure = error.localizedDescription
            }
        }
        .sheet(item: $naming, onDismiss: {
            if let recorded { self.recorded = nil; onAssign(recorded) }
        }) { target in
            SoundNameEditor(name: target.name, importing: target.isImport) { name in
                switch target {
                case .imported(let url):
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    recorded = try await store.upload(url, name: name)
                case .existing(let clip): try await store.renameClip(clip, name: name)
                }
            }
        }
        .alert("Couldn’t open sound", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }

        .confirmationDialog("Delete \(deleteClip?.name ?? "sound")?", isPresented: Binding(get: { deleteClip != nil }, set: { if !$0 { deleteClip = nil } }), titleVisibility: .visible) {
            Button("Delete sound", role: .destructive) {
                if let clip = deleteClip { Task { await store.deleteClip(clip) } }; deleteClip = nil
            }
        } message: { Text("Remove this sound from any buttons before deleting it.") }
    }
}

enum SoundNameTarget: Identifiable {
    case imported(URL)
    case existing(Clip)
    var id: String {
        switch self { case .imported(let url): url.absoluteString; case .existing(let clip): clip.id }
    }
    var name: String {
        switch self {
        case .imported(let url): String(url.deletingPathExtension().lastPathComponent.prefix(60))
        case .existing(let clip): clip.name
        }
    }
    var isImport: Bool { if case .imported = self { true } else { false } }
}

struct SoundNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    let importing: Bool
    let save: (String) async throws -> Void
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var focused: Bool
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sound name", text: $name).focused($focused).submitLabel(.done)
                        .onSubmit { if valid { submit() } }
                    Text("\(trimmed.utf16.count)/60").font(.caption).foregroundStyle(trimmed.utf16.count > 60 ? .red : .secondary)
                } header: { Text("Name your sound") } footer: {
                    Text(importing ? "Use a name you’ll recognize while playing. Next, customize its button. Audio can be up to 60 seconds and 20 MB." : "This changes the library name. Your buttons keep their own names and still play the same sound.")
                }
                if saving { HStack { ProgressView(); Text(importing ? "Importing sound…" : "Saving name…") } }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle(importing ? "Import sound" : "Rename sound").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(importing ? "Import" : "Save") { submit() }.fontWeight(.semibold).disabled(!valid)
                }
            }
            .onAppear { focused = true }
        }.interactiveDismissDisabled(saving)
    }
    private var valid: Bool { !saving && !trimmed.isEmpty && trimmed.utf16.count <= 60 }
    private func submit() {
        saving = true; failure = nil; focused = false
        Task {
            do { try await save(trimmed); dismiss() }
            catch { failure = error.localizedDescription }
            saving = false
        }
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
                        if name.utf16.count > 60 { Text("Use 60 characters or fewer.").font(.caption).foregroundStyle(.red) }
                        HStack(spacing: 12) {
                            Button { recorder.listen() } label: { Label("Listen", systemImage: "play.fill") }.buttonStyle(QuietButtonStyle())
                            Button { Task { await recorder.start() } } label: { Label("Retake", systemImage: "arrow.counterclockwise") }.buttonStyle(QuietButtonStyle())
                        }
                        Button { upload() } label: { Text(uploading ? "Saving…" : "Save & add button") }.buttonStyle(AccentButtonStyle())
                            .disabled(uploading || name.trimmingCharacters(in: .whitespaces).isEmpty || name.utf16.count > 60)
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
