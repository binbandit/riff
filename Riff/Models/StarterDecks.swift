import Foundation

extension Snapshot {
    static let starter = Snapshot(version: 0, decks: [
        Deck(id: "soundboard", name: "Soundboard", icon: "waveform", pads: [
            Pad(id: "level-up-pad", title: "Level up", icon: "sparkles", color: "orange", value: "level-up"),
            Pad(id: "plot-twist-pad", title: "Plot twist", icon: "theatermasks", color: "purple", value: "plot-twist"),
            Pad(id: "nope-pad", title: "Nope", icon: "hand.raised", color: "pink", value: "nope"),
            Pad(id: "countdown-pad", title: "Countdown", icon: "timer", color: "blue", value: "countdown"),
            Pad(id: "coin-drop-pad", title: "Coin drop", icon: "circle.circle", color: "green", value: "coin-drop"),
            Pad(id: "red-alert-pad", title: "Red alert", icon: "light.beacon.max", color: "orange", value: "red-alert")
        ]),
        Deck(id: "everyday", name: "Everyday", icon: "command", pads: [
            Pad(id: "play-pause-pad", title: "Play / pause", icon: "playpause", color: "green", kind: "media", value: "playPause"),
            Pad(id: "next-pad", title: "Next track", icon: "forward.end", color: "blue", kind: "media", value: "next"),
            Pad(id: "mute-pad", title: "Mute audio", icon: "speaker.slash", color: "pink", kind: "media", value: "mute"),
            Pad(id: "desktop-pad", title: "Show desktop", icon: "desktopcomputer", color: "purple", kind: "hotkey", value: "Win+D"),
            Pad(id: "screenshot-pad", title: "Screenshot", icon: "viewfinder", color: "orange", kind: "hotkey", value: "Win+Shift+S"),
            Pad(id: "gg-pad", title: "Good game", icon: "text.bubble", color: "green", kind: "text", value: "gg, well played!")
        ])
    ], clips: [Clip(id: "level-up", name: "Level up", duration: 0.76), Clip(id: "plot-twist", name: "Plot twist", duration: 1.21), Clip(id: "nope", name: "Nope", duration: 0.53), Clip(id: "countdown", name: "Countdown", duration: 1.8), Clip(id: "coin-drop", name: "Coin drop", duration: 0.39), Clip(id: "red-alert", name: "Red alert", duration: 1.44)] + SoundPacks.clips, outputs: [], outputId: "", volume: 0.75, apps: [], computerName: "", games: [], activeGameId: "", activeGameName: "")
}
