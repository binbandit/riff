// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RiffProtocol",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RiffProtocol", targets: ["RiffProtocol"])],
    targets: [
        .target(name: "RiffProtocol", path: "Riff", exclude: ["Assets.xcassets", "Sounds", "DesignPreview.swift", "GridLayoutView.swift", "SoundPickerView.swift", "ClipEditorView.swift", "AudioControlsView.swift", "ContentView.swift", "Editors.swift", "PairingScanner.swift", "Recorder.swift", "RiffStore.swift", "SettingsView.swift", "SoundLibrary.swift"], sources: ["Models.swift", "Connection.swift", "BoardLayout.swift", "SoundCatalog.swift", "ClipAudio.swift", "SoundPlayback.swift"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "RiffProtocolTests", dependencies: ["RiffProtocol"], path: "Tests/RiffProtocolTests")
    ]
)
