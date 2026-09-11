import AVFoundation
import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct ClipAudioTests {
    private func source(seconds: Int = 3) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
        buffer.frameLength = 8000
        let channels = try #require(buffer.floatChannelData)
        for second in 0..<seconds {
            for frame in 0..<8000 {
                channels[0][frame] = second == 1 ? 0.8 : 0.1
                channels[1][frame] = second == 1 ? 0.4 : 0.1
            }
            try file.write(from: buffer)
        }
        return url
    }

    @Test func exportsOnlyTheSelectedSamplesAndPreservesTheSource() throws {
        let input = try source()
        defer { try? FileManager.default.removeItem(at: input) }
        let original = try Data(contentsOf: input)
        let inspection = try ClipAudio.inspect(input)
        #expect(inspection.duration == 3)
        #expect(inspection.peaks.count == 100)
        #expect(inspection.peaks[50] > inspection.peaks[0])
        let output = try ClipAudio.export(input, start: 1, end: 2)
        defer { try? FileManager.default.removeItem(at: output) }
        let file = try AVAudioFile(forReading: output)
        #expect(file.length == 8000)
        #expect(file.processingFormat.channelCount == 1)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8000))
        try file.read(into: buffer)
        let samples = try #require(buffer.floatChannelData?[0])
        #expect(abs(samples[0] - 0.6) < 0.001)
        #expect(abs(samples[7999] - 0.6) < 0.001)
        #expect(try Data(contentsOf: input) == original)
    }

    @Test func rejectsInvalidRangesAndBoundsSixtySecondExports() throws {
        let input = try source(seconds: 62)
        defer { try? FileManager.default.removeItem(at: input) }
        for range in [(-1.0, 2.0), (2, 2), (0, 61), (0, 63), (Double.nan, 2)] {
            #expect(throws: (any Error).self) { try ClipAudio.export(input, start: range.0, end: range.1) }
        }
        let output = try ClipAudio.export(input, start: 0.13, end: 60.13)
        defer { try? FileManager.default.removeItem(at: output) }
        let file = try AVAudioFile(forReading: output)
        #expect(Double(file.length) / file.processingFormat.sampleRate <= 60)
        #expect(file.length > 479990)
    }
}
