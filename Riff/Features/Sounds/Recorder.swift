import AVFoundation
import Observation

@MainActor @Observable final class SnippetRecorder {
    var recording = false
    var elapsed: Double = 0
    var level: Float = 0
    var url: URL?
    var error: String?
    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var preview: AVAudioPlayer?
    func start() async {
        error = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Allow microphone access in iPad Settings > Apps > Riff to record a snippet."; return
        }
        do {
            cleanup()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let next = try AVAudioRecorder(url: target, settings: settings)
            next.isMeteringEnabled = true
            guard next.record(forDuration: 60) else { throw RiffError.message("The microphone could not start recording.") }
            recorder = next; url = target; recording = true; elapsed = 0
            meterTask = Task {
                while !Task.isCancelled, recording {
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled else { break }
                    next.updateMeters(); level = pow(10, next.averagePower(forChannel: 0) / 30)
                    elapsed = next.currentTime
                    if !next.isRecording { stop(); elapsed = 60 }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        recorder?.stop(); recording = false; meterTask?.cancel(); level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func listen() {
        guard let url else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            preview = try AVAudioPlayer(contentsOf: url); preview?.play()
        } catch { self.error = error.localizedDescription }
    }
    func stopListening() { preview?.stop(); preview = nil }
    func cleanup() {
        stop(); preview?.stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil; elapsed = 0
    }
}
