import Foundation
import Observation

@Observable @MainActor final class SoundBatchImport {
    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        var clip: Clip?
        var failure: String?
    }
    private(set) var items: [Item]
    private(set) var running = false
    private(set) var finished = false
    private(set) var currentID: UUID?
    var imported: [Clip] { items.compactMap(\.clip) }
    var completedCount: Int { items.filter { $0.clip != nil || $0.failure != nil }.count }

    init(urls: [URL]) {
        var seen = Set<URL>()
        items = urls.filter { seen.insert($0).inserted }.map { Item(url: $0) }
    }

    nonisolated static func soundName(for url: URL) -> String {
        let source = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = ""
        for character in source {
            guard name.utf16.count + String(character).utf16.count <= 60 else { break }
            name.append(character)
        }
        return name.isEmpty ? "Imported sound" : name
    }

    nonisolated static func prepare(_ url: URL) throws -> URL {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let inspection = try ClipAudio.inspect(url)
        guard inspection.duration <= 60 else {
            throw ClipAudioError.invalid("Import this file on its own to trim it to 60 seconds or less.")
        }
        return try ClipAudio.export(url, start: 0, end: inspection.duration)
    }

    func run(
        prepare: @escaping @Sendable (URL) throws -> URL = SoundBatchImport.prepare,
        upload: (URL, String) async throws -> Clip
    ) async {
        guard !running, !finished else { return }
        running = true
        defer { running = false; currentID = nil }
        for index in items.indices {
            guard !Task.isCancelled else { return }
            currentID = items[index].id
            let url = items[index].url
            do {
                let task = Task.detached(priority: .userInitiated) { try prepare(url) }
                let output = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                defer { try? FileManager.default.removeItem(at: output) }
                try Task.checkCancellation()
                items[index].clip = try await upload(output, Self.soundName(for: url))
            } catch {
                if Task.isCancelled { return }
                items[index].failure = error.localizedDescription
            }
        }
        finished = true
    }
}
