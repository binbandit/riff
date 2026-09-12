import AVFoundation
import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct SoundBatchImportTests {
    @Test func continuesAfterFailureKeepsOrderAndCleansPreparedFiles() async throws {
        let urls = ["first.wav", "broken.wav", "last.wav"].map { URL(fileURLWithPath: "/" + $0) }
        let batch = SoundBatchImport(urls: urls + [urls[0]])
        var uploadedNames: [String] = []
        var temporaryFiles: [URL] = []
        await batch.run(prepare: { _ in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data([1, 2, 3]).write(to: output)
            return output
        }) { output, name in
            temporaryFiles.append(output)
            uploadedNames.append(name)
            if name == "broken" { throw RiffError.message("Unsupported audio") }
            return Clip(id: name, name: name, duration: 1)
        }
        #expect(uploadedNames == ["first", "broken", "last"])
        #expect(batch.imported.map(\.id) == ["first", "last"])
        #expect(batch.items[1].failure == "Unsupported audio")
        #expect(batch.completedCount == 3 && batch.finished && !batch.running)
        #expect(temporaryFiles.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        await batch.run { _, _ in Issue.record("A finished import must not upload again"); throw CancellationError() }
    }

    @Test func preparationFailureDoesNotStopOtherFiles() async {
        let batch = SoundBatchImport(urls: [URL(fileURLWithPath: "/invalid.wav"), URL(fileURLWithPath: "/valid.wav")])
        await batch.run(prepare: { source in
            if source.lastPathComponent == "invalid.wav" { throw RiffError.message("Invalid audio") }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data().write(to: output)
            return output
        }) { _, name in Clip(id: name, name: name, duration: 1) }
        #expect(batch.items[0].failure == "Invalid audio")
        #expect(batch.imported.map(\.name) == ["valid"])
    }

    @Test func filenamesRespectWindowsNameLimit() {
        let emoji = URL(fileURLWithPath: "/" + String(repeating: "🎵", count: 40) + ".wav")
        #expect(SoundBatchImport.soundName(for: emoji) == String(repeating: "🎵", count: 30))
        #expect(SoundBatchImport.soundName(for: URL(fileURLWithPath: "/   .wav")) == "Imported sound")
    }

    @Test func preparesWholeClipAndRejectsLongAudioWithoutTruncating() throws {
        for seconds in [2, 61] {
            let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
            defer { try? FileManager.default.removeItem(at: source) }
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
            do {
                let file = try AVAudioFile(forWriting: source, settings: format.settings)
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 8000)))
                buffer.frameLength = buffer.frameCapacity
                let samples = try #require(buffer.floatChannelData?[0])
                for frame in 0..<Int(buffer.frameLength) { samples[frame] = 0.25 }
                try file.write(from: buffer)
            }
            let original = try Data(contentsOf: source)
            if seconds > 60 {
                #expect(throws: ClipAudioError.self) { try SoundBatchImport.prepare(source) }
            } else {
                let output = try SoundBatchImport.prepare(source)
                defer { try? FileManager.default.removeItem(at: output) }
                #expect(try ClipAudio.inspect(output).duration == Double(seconds))
            }
            #expect(try Data(contentsOf: source) == original)
        }
    }
}
