# Verification

## Completed in this workspace

- Windows companion Debug build: successful, zero compiler warnings/errors.
- Windows x64 Release publish: successful, self-contained executable produced with its starter sound assets.
- Core rules: 25 tests passed, including action bounds, shortcut parsing, app allowlisting, invalid URL/path rejection, unique IDs, wire-format round trips, reordering preserving actions, stopping only the tapped button, overlap and replacement modes, mixer capacity, and legacy trigger requests.
- Swift protocol, transport, and grid layout: 19 tests passed, covering pairing-link validation, malformed links, Steam/deck persistence, starter sound references, independent button duplication and long Unicode names, cross-deck moves and copies, full-deck handling, favorites/search filtering and sequence sound references, real PCM trimming with waveform peaks, stereo-to-mono export, unchanged source files and the 60-second boundary, grid rotation, custom capacity in small windows, per-deck settings serialization, and a live loopback HTTPS test of certificate pinning, invalid access keys, and redirect rejection, playback revision ordering, companion restarts, and older snapshots without playback capabilities. The loopback server is a test fixture, not the Windows companion.
- Native iPad simulator build: successful with Xcode 27 / iOS 27 SDK.
- Native iPad device Release build: successful without code signing. An unsigned IPA was packaged for user signing. This is a compile/package check, not an installed physical-device build.
- iPad app installed and launched in an iPad Pro 11-inch (M5) simulator. The redesigned main screen, sound library, recording sheet, grid-size sheet, sound-renaming sheet, updated library filters, quick audio controls with overlap/one-at-a-time selection, and the waveform clip editor were visually inspected. Grid interaction testing through computer use remains blocked by Device Hub attachment failures. See [the actual simulator capture](screenshots/ipad-preview.png). It is an offline preview, not a simulated PC connection.
- A DEBUG simulator smoke check exercised the app store with real bundled audio: two overlapping sounds, stopping only the tapped sound, replacing playback in single mode, natural completion, and Stop All. All six assertions passed (including no playback errors). This invokes app actions directly; it is not a computer-use tap-through test.
- Windows HTTPS integration-test project: compiled successfully. It must run on Windows; it was not executed on this Mac.

Xcode emits an informational warning that App Intents metadata extraction is skipped because the app does not use AppIntents. There were no Swift compiler warnings.

## Required device checks

These need a Windows 11 PC and a physical iPad. They have not been claimed as completed here.

1. Run `dotnet test Companion/Riff.WindowsTests` on Windows, with the normal companion closed. This uses the real HTTPS server and verifies authorization (including playback status), advertised playback capability, invalid playback-mode rejection, deck saves, stale-write rejection, sound renaming without changing button references, rename validation, persistence, invalid actions, upload-type rejection, Stop All, and pairing revocation. It does not send keyboard input or require game access.
2. Sign and install the iPad app. Scan the PC's QR code, connect, close/reopen the app, and confirm automatic reconnection.
3. Select speakers in audio settings, apply, and play a starter sound. Test overlap and one-at-a-time modes, tapping a playing pad again, natural completion indicators, library previews, volume, and Stop All. Confirm sounds can be stopped and played while a delayed sequence is running. Disconnect an output during playback and confirm Stop All and subsequent playback recover.
4. Record a snippet, trim it, listen locally, save it, assign the resulting button, and play it on Windows. Verify trimming a longer imported clip, canceling the editor, changing selection during local preview, and returning to a recording without losing it. Import a short MP3/WAV. Confirm overlong or unsupported files produce a readable error.
5. Configure VB-CABLE and verify a clip in the game's actual microphone test, then in a lobby. Check push-to-talk/voice activation and noise processing.
6. Add and rearrange buttons. Reopen both apps and confirm the order, names, colors, and actions persist.
7. Link a Steam game, launch it from Steam, and verify its deck opens. Manually switch away and confirm it stays selected until a new game is detected. Test no Steam, an unlinked game, and multiple running games.
8. In a text editor, test a shortcut and a text button. Add an approved application and test its launcher. Test a delayed sequence and cancel it halfway with Stop All.
9. Revoke pairing on Windows and verify the previous link is rejected. Pair again. Disconnect Wi-Fi and verify clear offline status without queued/replayed actions.
10. Check landscape, portrait, Split View, larger text sizes, VoiceOver, physical-device microphone/camera permissions, and drag/drop behavior. Only the first portrait screen has been visually inspected locally.

## Current limits

- The app must stay open on iPad to act as a control surface; it is not a background remote service.
- One selected sound output. Dual-output monitoring and live-mic mixing use Windows or an external mixer.
- Shortcut taps only; push-to-talk must be held physically or voice activation enabled.
- Common button actions are implemented, not Elgato plugin compatibility, mouse controls, automatic foreground-app profiles, or a dedicated OBS API client.
- Steam running-state detection uses an undocumented local registry layout and needs physical validation.
- Local-network reachability, audio device behavior, Windows input permissions, and game anti-cheat restrictions cannot be established by a macOS cross-build.
