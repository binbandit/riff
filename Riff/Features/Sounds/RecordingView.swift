import SwiftUI

struct RecordingView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = SnippetRecorder()
    @State private var name = ""
    @State private var editingClip = false
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
                                .frame(width: 4, height: waveformHeight(at: index))
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
                        Button { recorder.stopListening(); editingClip = true } label: { Text("Trim & add button") }.buttonStyle(AccentButtonStyle())
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name.utf16.count > 60)
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
                    if let text = recorder.error { Text(text).font(.subheadline).foregroundStyle(.red).multilineTextAlignment(.center) }
                }.padding(28).frame(maxWidth: .infinity)
            }.background(Palette.background)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .navigationDestination(isPresented: $editingClip) {
                    if let url = recorder.url { ClipEditorView(url: url, name: name, onSaved: onRecorded) }
                }
        }
        .interactiveDismissDisabled(recorder.recording)
#if DEBUG
        .task {
            if DesignPreview.screen == "recording-trim", let source = Bundle.main.url(forResource: "level-up", withExtension: "wav") {
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
                do {
                    try FileManager.default.copyItem(at: source, to: copy)
                    recorder.url = copy; name = "Level up"; editingClip = true
                } catch { recorder.error = error.localizedDescription }
            }
        }
#endif
        .onDisappear { recorder.cleanup() }
        .onChange(of: scenePhase) { _, phase in if phase != .active && recorder.recording { recorder.stop() } }
    }

    private func waveformHeight(at index: Int) -> CGFloat {
        guard recorder.recording else { return 5 }
        let variation = 0.35 + abs(sin(Double(index) * 1.8))
        let height = Double(recorder.level) * 100 * variation
        return max(5, CGFloat(height))
    }
}
