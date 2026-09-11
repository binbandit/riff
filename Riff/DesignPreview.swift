#if DEBUG
import SwiftUI

// Launch-only preview settings for repeatable simulator captures. No simulated PC connection.
enum DesignPreview {
    static let screen = ProcessInfo.processInfo.environment["RIFF_PREVIEW_SCREEN"] ?? ""
    static let markdown = """
    # Markdown preview

    **Bold**, *italic*, ~~removed~~, and `inline code`.

    - Layer sound effects
      - Keep nested details readable
    1. Pick a sound
    2. Tap to play

    > A quoted note with a [release link](https://github.com/binbandit/riff/releases).

    ```text
    Output: CABLE Input
    Playback: One at a time
    ```

    | Mode | Behavior |
    | --- | --- |
    | Overlap | Layer sounds |
    | Single | Replace the last sound |

    - [x] Downloaded changelog
    - [ ] Install companion update
    """
    static var colorScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["RIFF_PREVIEW_APPEARANCE"] {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
    @MainActor static func configurePages(_ store: RiffStore) {
        guard !store.paired else { return }
        var deck = Snapshot.starter.decks[0]
        deck.name = "Page preview"
        deck.pads = (0..<3).flatMap { page in
            Snapshot.starter.decks[0].pads.map { pad in
                var copy = pad
                copy.id = "page-\(page)-\(pad.id)"
                return copy
            }
        }
        store.snapshot.decks[0] = deck
        store.selectedDeckId = deck.id
    }
    @MainActor static func checkPlayback(_ store: RiffStore) async {
        guard !store.paired else { return }
        let originalMode = store.soundMode
        defer { store.soundMode = originalMode }
        var results: [String: Bool] = [:]
        let countdown = Snapshot.starter.decks[0].pads[3]
        let alert = Snapshot.starter.decks[0].pads[5]
        await store.stopAll()
        store.soundMode = .overlap
        await store.trigger(countdown); await store.trigger(alert)
        results["overlap"] = store.playingPadIDs == [countdown.id, alert.id]
        await store.trigger(countdown)
        results["toggleKeepsOtherSound"] = store.playingPadIDs == [alert.id]
        store.soundMode = .single
        await store.trigger(countdown)
        results["singleReplaces"] = store.playingPadIDs == [countdown.id]
        try? await Task.sleep(for: .seconds(2.2))
        await store.refreshPlayback()
        results["naturalCompletion"] = store.playingPadIDs.isEmpty
        await store.trigger(countdown)
        await store.stopAll(); await store.refreshPlayback()
        results["stopAll"] = store.playingPadIDs.isEmpty
        results["noErrors"] = store.error == nil
        let file = URL.cachesDirectory.appendingPathComponent("playback-check.json")
        do { try JSONEncoder().encode(results).write(to: file) }
        catch { NSLog("Playback check could not save: %@", error.localizedDescription) }
    }
    static func orient() {
        guard ProcessInfo.processInfo.environment["RIFF_PREVIEW_ORIENTATION"] == "landscape",
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft)) { error in
            NSLog("Riff preview orientation: %@", error.localizedDescription)
        }
    }
}
#endif
