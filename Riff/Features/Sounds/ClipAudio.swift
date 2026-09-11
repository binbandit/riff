import AVFoundation
import Foundation

nonisolated struct ClipInspection: Sendable {
    let duration: Double
    let peaks: [Float]
}

nonisolated enum ClipAudioError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}

nonisolated enum ClipAudio {
    static func inspect(_ url: URL) throws -> ClipInspection {
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 100 * 1024 * 1024 {
            throw ClipAudioError.invalid("Choose an audio file smaller than 100 MB.")
        }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration >= 0.05, duration <= 600 else {
            throw ClipAudioError.invalid("Choose audio between 0.05 seconds and 10 minutes long, then trim it to 60 seconds or less.")
        }
        guard file.processingFormat.sampleRate <= 96000, file.processingFormat.channelCount <= 8 else {
            throw ClipAudioError.invalid("Use audio at 96 kHz or below, with up to 8 channels.")
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { throw ClipAudioError.invalid("This audio format couldn’t be opened.") }
        var peaks = [Float](repeating: 0, count: 100)
        var position: AVAudioFramePosition = 0
        while position < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(8192, file.length - position)))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for frame in 0..<Int(buffer.frameLength) {
                let bin = min(99, Int((position + Int64(frame)) * 100 / file.length))
                for channel in 0..<Int(buffer.format.channelCount) { let sample = channels[channel][frame]; if sample.isFinite { peaks[bin] = max(peaks[bin], abs(sample)) } }
            }
            position += Int64(buffer.frameLength)
        }
        return ClipInspection(duration: duration, peaks: peaks)
    }

    static func export(_ url: URL, start: Double, end: Double) throws -> URL {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let rate = file.processingFormat.sampleRate
        let duration = Double(file.length) / rate
        guard start.isFinite, end.isFinite, start >= 0, end <= duration + 0.000001,
              end > start, end - start <= 60.000001, rate > 0, rate <= 96000,
              file.processingFormat.channelCount <= 8 else { throw ClipAudioError.invalid("Select up to 60 seconds within the source audio.") }
        let first = Int64((start * rate).rounded(.up))
        let last = min(file.length, first + Int64((60 * rate).rounded(.down)), Int64((end * rate).rounded(.down)))
        guard last > first else { throw ClipAudioError.invalid("Select a longer part of the sound.") }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        do {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let output = try AVAudioFile(forWriting: target, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192),
                  let mono = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: 8192) else { throw ClipAudioError.invalid("This audio format couldn’t be edited.") }
            file.framePosition = first
            var remaining = last - first
            while remaining > 0 {
                try Task.checkCancellation()
                try file.read(into: input, frameCount: AVAudioFrameCount(min(8192, remaining)))
                guard input.frameLength > 0, let channels = input.floatChannelData, let samples = mono.floatChannelData?[0] else { throw ClipAudioError.invalid("The audio ended before the selected endpoint.") }
                mono.frameLength = input.frameLength
                for frame in 0..<Int(input.frameLength) {
                    var sample: Float = 0
                    for channel in 0..<Int(input.format.channelCount) { sample += channels[channel][frame] / Float(input.format.channelCount) }
                    samples[frame] = sample.isFinite ? min(1, max(-1, sample)) : 0
                }
                try output.write(from: mono)
                remaining -= Int64(input.frameLength)
            }
            return target
        } catch { try? FileManager.default.removeItem(at: target); throw error }
    }
}
