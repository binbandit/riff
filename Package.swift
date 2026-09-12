// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RiffProtocol",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RiffProtocol", targets: ["RiffProtocol"])],
    targets: [
        .target(
            name: "RiffProtocol",
            path: "Riff",
            exclude: [
                "App/RiffApp.swift",
                "Design/ButtonStyles.swift",
                "Design/PadGlyph.swift",
                "Features/Audio",
                "Features/Connection/ConnectionView.swift",
                "Features/Connection/PairingScanner.swift",
                "Features/Decks/ActionFields.swift",
                "Features/Decks/ButtonPresetsView.swift",
                "Features/Decks/ContentView.swift",
                "Features/Decks/DeckEditor.swift",
                "Features/Decks/GridLayoutView.swift",
                "Features/Decks/PadAppearanceEditor.swift",
                "Features/Decks/PadEditor.swift",
                "Features/Decks/SequenceEditor.swift",
                "Features/Decks/LayoutSharingView.swift",
                "Features/Decks/PadTile.swift",
                "Features/Settings",
                "Features/Sounds/AddSoundsView.swift",
                "Features/Sounds/ClipEditorView.swift",
                "Features/Sounds/LibraryView.swift",
                "Features/Sounds/ImportSoundsView.swift",
                "Features/Sounds/Recorder.swift",
                "Features/Sounds/RecordingView.swift",
                "Features/Sounds/SoundNameEditor.swift",
                "Features/Sounds/SoundGroupsView.swift",
                "Features/Sounds/SoundPickerView.swift",
                "Features/Updates/CompanionChangelogView.swift",
                "Features/Updates/CompanionUpdatesView.swift",
                "Preview",
                "Resources/Assets.xcassets",
                "Resources/MarkdownLicenses.txt",
                "Resources/Sounds"
            ],
            sources: [
                "App/RiffStore.swift",
                "Design/Theme.swift",
                "Models",
                "Features/Connection/Connection.swift",
                "Features/Decks/BoardLayout.swift",
                "Features/Sounds/ClipAudio.swift",
                "Features/Sounds/SoundBatchImport.swift",
                "Features/Sounds/SoundCatalog.swift",
                "Features/Sounds/SoundDeckBuilder.swift",
                "Features/Sounds/SoundPacks.swift",
                "Features/Sounds/SoundPlayback.swift",
                "Features/Updates/CompanionRelease.swift",
                "Features/Updates/CompanionUpdates.swift",
                "Features/Updates/MarkdownDisplay.swift",
                "Features/Updates/ReleaseChangelog.swift"
            ],
            resources: [.process("Resources/sound-packs.json"), .process("Resources/PackSounds")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "RiffProtocolTests",
            dependencies: ["RiffProtocol"],
            path: "Tests/RiffProtocolTests"
        )
    ]
)
