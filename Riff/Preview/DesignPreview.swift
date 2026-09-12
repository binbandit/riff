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
    @MainActor static func configureActions(_ store: RiffStore) {
        guard !store.paired else { return }
        store.snapshot.capabilities = ["deck-actions-v1", "smart-profiles-v1", "pinned-pads-v1"]
        store.snapshot.apps = [LaunchApp(id: "obs", name: "OBS Studio")]
        store.snapshot.decks[0].name = "Studio controls"
        store.snapshot.decks[0].linkedAppId = "obs"
        store.snapshot.decks[0].pads = [
            Pad(title: "Stream on / off", icon: "switch.2", color: "purple", kind: "switch", value: "",
                steps: [ActionStep(kind: "hotkey", value: "Ctrl+Shift+S")],
                alternateSteps: [ActionStep(kind: "hotkey", value: "Ctrl+Shift+E")]),
            Pad(title: "Surprise me", icon: "shuffle", color: "pink", kind: "random", value: "",
                steps: [ActionStep(kind: "sound", value: "nope"), ActionStep(kind: "sound", value: "level-up")]),
            Pad(title: "Everyday", icon: "folder", color: "blue", kind: "deck", value: "everyday"),
            Pad(title: "Go back", icon: "arrow.uturn.backward", color: "green", kind: "back", value: ""),
            Pad(title: "Stop all", icon: "stop.fill", color: "orange", kind: "stop", value: ""),
            Pad(title: "Level up", icon: "sparkles", color: "orange", kind: "sound", value: "level-up")
        ]
        store.switchedPadIDs = [store.snapshot.decks[0].pads[0].id]
        store.selectedDeckId = store.snapshot.decks[0].id
    }
    @MainActor static func configureKeyLogic(_ store: RiffStore) {
        guard !store.paired else { return }
        configureActions(store)
        store.snapshot.capabilities?.append("key-logic-v1")
        store.snapshot.decks[0].name = "One button, three actions"
        store.snapshot.decks[0].pads[0] = Pad(title: "Music", icon: "playpause", color: "purple", kind: "media", value: "playPause",
            doubleTapAction: PadGestureAction(kind: "media", value: "next"), holdAction: PadGestureAction(kind: "media", value: "previous"))
        store.snapshot.decks[0].pads[1] = Pad(title: "Tap · double · hold", icon: "hand.tap", color: "pink", kind: "sound", value: "countdown",
            doubleTapAction: PadGestureAction(kind: "deck", value: "everyday"), holdAction: PadGestureAction(kind: "stop", value: ""))
    }
    @MainActor static func configurePinnedPages(_ store: RiffStore) {
        guard !store.paired else { return }
        configurePages(store)
        store.snapshot.capabilities = ["deck-actions-v1", "pinned-pads-v1"]
        store.snapshot.decks[0].name = "Always in reach"
        store.snapshot.decks[0].pads[0] = Pad(title: "Stop all", icon: "stop.fill", color: "pink", kind: "stop", value: "", pinned: true)
        store.snapshot.decks[0].pads[1] = Pad(title: "Everyday", icon: "folder", color: "purple", kind: "deck", value: "everyday", pinned: true)
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
