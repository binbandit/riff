import SwiftUI
import AVFoundation

struct ClipEditorView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let url: URL
    @State var name: String
    var onSaved: (Clip) -> Void
    @State private var inspection: ClipInspection?
    @State private var start = 0.0
    @State private var length = 1.0
    @State private var busy = false
    @State private var playing = false
    @State private var failure: String?
    @State private var access = false
    @State private var player: AVAudioPlayer?
    @State private var previewURL: URL?
    @State private var work: Task<Void, Never>?
    @State private var operation = UUID()
    @FocusState private var editingTime: Bool
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Sound name", text: $name).font(.title2.weight(.semibold))
                    .padding(18).background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                    .disabled(busy)
                if cleanName.utf16.count > 60 { Text("Use 60 characters or fewer.").font(.caption).foregroundStyle(.red) }
                if let inspection {
                    VStack(spacing: 18) {
                        waveform(inspection)
                            .frame(height: 96).accessibilityLabel("Audio waveform; selected from \(time(start)) to \(time(start + length))")
                        HStack {
                            Text(time(start)); Spacer()
                            Text("\(length, specifier: "%.2f") seconds").fontWeight(.semibold)
                            Spacer(); Text(time(start + length))
                        }.font(.subheadline).monospacedDigit()
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Start point").font(.subheadline.weight(.medium))
                                Spacer()
                                TextField("Seconds", value: Binding(get: { start }, set: { if $0.isFinite { start = min(max(0, $0), inspection.duration - 0.05) } }), format: .number.precision(.fractionLength(2)))
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90).focused($editingTime).accessibilityLabel("Start point in seconds")
                                Text("sec").font(.caption).foregroundStyle(.secondary)
                            }
                            Slider(value: $start, in: 0...max(0.001, inspection.duration - 0.05))
                                .accessibilityLabel("Start point").accessibilityValue("\(time(start))")
                                .onChange(of: start) { _, _ in stopPreview(); length = min(length, inspection.duration - start) }
                            HStack {
                                Text("Clip length").font(.subheadline.weight(.medium))
                                Spacer()
                                TextField("Seconds", value: Binding(get: { length }, set: { if $0.isFinite { length = min(max(0.01, $0), min(60, inspection.duration - start)) } }), format: .number.precision(.fractionLength(2)))
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90).focused($editingTime).accessibilityLabel("Clip length in seconds")
                                Text("sec").font(.caption).foregroundStyle(.secondary)
                            }
                            Slider(value: $length, in: 0.01...max(0.01, min(60, inspection.duration - start)))
                                .accessibilityLabel("Clip length").accessibilityValue("\(length, specifier: "%.2f") seconds")
                                .onChange(of: length) { _, _ in stopPreview() }
                        }.disabled(busy)
                    }.padding(18).background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))
                    HStack {
                        Button {
                            if playing { stopPreview() } else { preview() }
                        } label: {
                            Label(playing ? "Stop preview" : "Listen on iPad", systemImage: playing ? "stop.fill" : "play.fill")
                        }.buttonStyle(AccentButtonStyle()).disabled(busy)
                        Spacer()
                        Button("Reset") { stopPreview(); start = 0; length = min(60, inspection.duration) }.disabled(busy)
                    }
                    Label("This preview stays on your iPad. It isn’t sent to game chat.", systemImage: "ipad")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Only the selected section is saved. Your original file stays unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if failure == nil {
                    ProgressView("Reading audio…").frame(maxWidth: .infinity, minHeight: 180)
                }
                if busy { ProgressView("Preparing sound…") }
                if let failure { Text(failure).foregroundStyle(.red).font(.subheadline) }
            }.padding(24)
        }
        .background(Palette.background)
        .navigationTitle("Edit sound").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingTime = false } }
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save & add") { save() }.fontWeight(.semibold)
                    .disabled(busy || inspection == nil || cleanName.isEmpty || cleanName.utf16.count > 60 || !store.connected)
            }
        }
        .interactiveDismissDisabled(busy)
        .task {
            access = url.startAccessingSecurityScopedResource()
            let task = Task.detached(priority: .userInitiated) { [url] in try ClipAudio.inspect(url) }
            do {
                let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                guard !Task.isCancelled else { return }
                inspection = result; length = min(60, result.duration)
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
        .onDisappear { stopPreview(); if access { url.stopAccessingSecurityScopedResource(); access = false } }
        .onChange(of: scenePhase) { _, phase in if phase != .active && !busy { stopPreview() } }
    }

    private func waveform(_ inspection: ClipInspection) -> some View {
        Canvas { context, size in
            let step = size.width / CGFloat(inspection.peaks.count)
            let peak = max(0.01, inspection.peaks.max() ?? 1)
            for (index, sample) in inspection.peaks.enumerated() {
                let position = Double(index) / Double(inspection.peaks.count) * inspection.duration
                let selected = position + inspection.duration / Double(inspection.peaks.count) > start && position < start + length
                let height = max(3, CGFloat(sample / peak) * (size.height - 12))
                let bar = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2, width: max(1, step - 2), height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: 2), with: .color(selected ? Palette.accent : Color.secondary.opacity(0.2)))
            }
        }
    }
    private func time(_ seconds: Double) -> String {
        String(format: "%d:%05.2f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
    private func exportSelection() async throws -> URL {
        let task = Task.detached(priority: .userInitiated) { [url, start, length] in try ClipAudio.export(url, start: start, end: start + length) }
        return try await withTaskCancellationHandler {
            let output = try await task.value
            if Task.isCancelled { try? FileManager.default.removeItem(at: output); throw CancellationError() }
            return output
        } onCancel: { task.cancel() }
    }
    private func stopPreview() {
        operation = UUID(); work?.cancel(); work = nil; player?.stop(); player = nil; playing = false; busy = false
        if let previewURL { try? FileManager.default.removeItem(at: previewURL); self.previewURL = nil }
    }
    private func preview() {
        editingTime = false; stopPreview(); busy = true; failure = nil
        let token = operation
        work = Task {
            defer { if operation == token { busy = false } }
            do {
                let output = try await exportSelection()
                guard operation == token, !Task.isCancelled else { try? FileManager.default.removeItem(at: output); return }
                previewURL = output
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
                let next = try AVAudioPlayer(contentsOf: output)
                guard next.play() else { throw ClipAudioError.invalid("The preview couldn’t start.") }
                player = next; playing = true; busy = false
                while next.isPlaying && !Task.isCancelled { try await Task.sleep(for: .milliseconds(100)) }
                if operation == token { stopPreview() }
            } catch {
                if !Task.isCancelled && operation == token { failure = error.localizedDescription; stopPreview() }
            }
        }
    }
    private func save() {
        editingTime = false; stopPreview(); busy = true; failure = nil
        let token = operation
        work = Task {
            defer { if operation == token { busy = false } }
            do {
                let output = try await exportSelection()
                defer { try? FileManager.default.removeItem(at: output) }
                let clip = try await store.upload(output, name: cleanName)
                if operation == token && !Task.isCancelled { onSaved(clip) }
            } catch { if !Task.isCancelled && operation == token { failure = error.localizedDescription } }
        }
    }
}
