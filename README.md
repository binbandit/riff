# Riff

Riff turns your iPad into a soundboard and control deck for your Windows PC. Play clips in game chat, trigger keyboard shortcuts, launch apps, or put a few repetitive actions behind one button.

It's a native SwiftUI app with a Windows companion. Both run on your own devices, over your local network. No account or subscription required.

<p align="center">
  <img src="docs/screenshots/ipad-preview.png" alt="Riff on iPad, showing six colorful sound buttons and recording and playback controls" width="420">
</p>

## What it does

- **Soundboard:** play overlapping clips or one at a time, tap a playing button to stop it, or stop everything at once. Six original sounds are included.
- **Recording and imports:** record on your iPad or import WAV, MP3, M4A, AAC, and AIFF files. Trim clips with a waveform editor and listen before saving.
- **Private previews:** library previews play on your iPad, even while connected to your PC. Imported and recorded sounds require a companion with iPad preview support. Deck buttons and explicit PC audio tests use your saved Windows output.
- **Custom decks:** choose button colors, symbols, and emoji; rearrange buttons; adjust the grid; and add several sounds to a deck at once.
- **PC controls:** send keyboard shortcuts, type text, control media, open websites, and launch apps you've approved on Windows. Chain up to 20 actions into a sequence.
- **Steam decks:** link a deck to a Steam game and switch to it automatically when the game starts.
- **Voice chat:** send clips to a virtual microphone for Discord or in-game chat. This needs a separate audio driver; setup is below.

Riff is still early. Builds and automated tests cover parts of the app, but physical iPad and Windows testing is still needed. The [verification notes](docs/VERIFICATION.md) track those gaps. Bug reports and device-testing feedback are welcome.

## Get started

You'll need an iPad running **iPadOS 17 or later** and a **Windows 11** PC on the same local network. The iPad app needs to stay open while you use it as a control deck.

### Windows

Download the companion from [GitHub Releases](https://github.com/binbandit/riff/releases/latest):

- `Riff-<version>-win-x64.zip` for Intel or AMD PCs.
- `Riff-<version>-win-arm64.zip` for ARM PCs.

1. Extract the whole ZIP. Keep the `Sounds` folder beside `Riff.Companion.exe`.
2. Run `Riff.Companion.exe`. The download includes .NET, so you don't need to install a runtime.
3. Allow Riff through Windows Firewall on **Private** networks.
4. Under **Connect iPad**, select your PC's home Wi-Fi or Ethernet address, rather than a VPN address.

The Windows build is unsigned. Closing the window leaves Riff running in the system tray; choose **Quit Riff** from the tray menu to exit.

If a release isn't available yet, development downloads are attached to successful runs of [Build and release Windows companion](https://github.com/binbandit/riff/actions/workflows/companion.yml). Downloading workflow artifacts requires a GitHub account.

### iPad

The iPad app currently needs signing with your own Apple account. There are two ways to install it.

**From a Mac:** clone this repository and open `Riff.xcodeproj` in Xcode. Choose your Apple development team under **Signing & Capabilities**, changing the bundle identifier if Xcode requests it. Connect your iPad, select it as the run destination, and run the app. Use Xcode with Swift 6.2 or later.

**From Windows:** download `Riff-iPad-unsigned.ipa` from a successful [Build and test iPad](https://github.com/binbandit/riff/actions/workflows/build.yml) run. Install [Sideloadly](https://sideloadly.io/), follow its device-driver setup instructions, then connect your iPad by USB and trust the PC. Load the IPA in Sideloadly and sign it with your Apple account. This installation route still needs physical-device testing for Riff.

Enable Developer Mode and trust the development app if prompted. Allow local-network access when you open Riff; microphone and camera permissions are requested when you record or scan a pairing code.

Free Apple signing expires after **7 days**, so you'll need to sign the app again or set up a refresh tool. See [Apple's account details](https://developer.apple.com/help/account/basics/about-your-developer-account) and the [Sideloadly FAQ](https://sideloadly.io/faq) for signing and refresh requirements.

### Connect your PC

On iPad, tap **Connect your PC**, scan the companion's QR code, then tap **Connect PC**. You can also paste the pairing link if scanning isn't available.

Keep that link and QR code private: they grant access to your PC controls. Pairing uses an access key and HTTPS with certificate pinning. The iPad stores the pairing details in Keychain; Windows protects its key with your Windows user account. Use **Revoke paired devices** in the companion to invalidate old links.

If the connection fails, check that both devices are on the same network, local-network permission is enabled on iPad, and Windows Firewall allows Riff on private networks. Guest Wi-Fi may block devices from reaching each other. If the PC's IP address changes, scan a new pairing code.

An optional [firewall script](scripts/allow-private-network.ps1) can add a rule for the executable on TCP port 49321, limited to private networks and the local subnet. Run it in an administrator PowerShell with the full executable path. Riff is intended for your local network; don't forward that port on your router.

## Using the soundboard

To add several library sounds to a board, open **+ → Add sounds from library** on the board, select sounds (or **Select shown**), then tap **Add … to [deck name]**. In the Sounds library, **Quick add** opens the same selection flow. Buttons follow selection order, existing sound buttons are skipped, and each deck holds up to 48 buttons. You can also choose another deck or create one.

For files, use **Sounds → + → Import audio files** and select several at once, then **Import all**. Filenames become sound names, progress and individual failures are shown, and successful imports can be added to a deck together. Files longer than 60 seconds must be imported individually for trimming. The Windows companion’s **Import sounds from PC** also accepts multiple files.

Tap the output label below the deck, or open **… → Sound controls**, to choose volume, output, and playback mode. **Overlap** layers effects; **One at a time** replaces the previous clip. **Stop all** stops sounds and cancels any remaining sequence steps.

Recordings and saved clips can be up to 60 seconds long. On iPad, you can import a file up to 10 minutes long and 100 MB in size, at 96 kHz or below, then trim it before upload. Direct Windows imports are limited to 20 MB and 60 seconds. Trimming leaves the original file unchanged.

Use **Sounds → Select → Add to deck** to build a deck from several clips. Favorites and search help you find them again. Long-press a button to duplicate it, or change its deck in the editor to move it. **… → Grid size** sets the rows and columns for each deck.

Without a PC connection, you can try the starter sounds on the iPad. Editing and PC actions need a connection.

### Send clips to voice chat

With [VB-CABLE](https://vb-audio.com/Cable/) installed on Windows, the audio route is:

**Riff → CABLE Input → CABLE Output → your chat app's microphone input**

1. In Riff's Windows audio settings, select **CABLE Input** and apply the change.
2. In Discord or your game, select **CABLE Output** as the microphone.
3. Open the chat app's microphone test and play a sound from Riff.
4. Use voice activation, or hold your push-to-talk key while the clip plays. Riff sends shortcut taps, so it can't hold that key for you.

If clips get cut off, check the chat app's voice threshold and noise suppression settings. To hear the clips yourself, enable **Listen to this device** for **CABLE Output** in Windows sound settings and select your headphones. Monitoring this way can add latency.

Riff has one playback output and doesn't mix your microphone with clips. For both at once, you'll need a separate mixer, such as [Voicemeeter](https://vb-audio.com/Voicemeeter/). These audio tools are separate downloads and aren't bundled with Riff.

### Steam and other controls

Link a game under **Deck settings**, then enable **Follow my Steam game** in Settings. Riff reads Steam's local library and running-game data; it doesn't need your Steam login or an API key. Detection is best effort. If several games are running, select a deck manually.

Keyboard shortcuts and typed text go to the focused Windows app. To launch an application, first add its `.exe` under **Allowed apps** in the companion. Riff doesn't accept arbitrary shell commands from the iPad.

Riff doesn't run Elgato plugins or include a dedicated OBS integration. You can control OBS through its configured hotkeys. Elevated applications and protected games may block simulated input.

## Updates and backups

The iPad checks GitHub for new companion releases while Riff is open and paired. You can also check under **Settings → Companion updates**. To update Windows, quit Riff from the tray, extract the new ZIP into a new folder, and run the new executable. Your decks and clips stay in place. See [companion update details](docs/COMPANION-UPDATES.md).

Playback and PC controls work without internet access. Update checks contact GitHub, but don't send your pairing key, PC address, decks, or sounds.

Windows stores decks, clips, settings, and approved app paths in `%LOCALAPPDATA%\Riff`. Close Riff before backing up that folder. To move to another PC or Windows account, copy `state.json` and `clips` into a fresh Riff data folder, then pair again. Don't copy the protected identity files. App paths and audio-device settings may need updating.

## Development

The iPad app lives in `Riff/`, the C# Windows companion in `Companion/`, and the bundled sounds in `Shared/Sounds/`. Swift tests are in `Tests/`; companion tests live alongside the C# projects.

The iPad source is grouped by responsibility:

```text
Riff/
├── App/          App entry point and shared store
├── Models/       Decks, pads, clips, and companion snapshots
├── Design/       Themes, button styles, and shared glyphs
├── Features/
│   ├── Audio/       Playback controls and microphone/music setup
│   ├── Connection/  Pairing, QR scanning, and secure transport
│   ├── Decks/       Main board, layout, and button/deck editors
│   ├── Settings/    Preferences and appearance
│   ├── Sounds/      Library, recording, trimming, and sound packs
│   └── Updates/     Companion releases and Markdown changelogs
├── Preview/      Development preview scenarios
└── Resources/    Asset catalog, starter and pack audio, sound-pack catalog, and licenses
```

Keep feature-specific views and supporting logic together. Put app-wide models and reusable visual components in `Models/` and `Design/`. Xcode discovers files inside `Riff/` automatically; update `Package.swift` when adding portable code or excluding an iPad-only view from the Mac test target. The sound generator writes starter audio to both `Shared/Sounds/` and `Riff/Resources/Sounds/`.

Clone the repository first:

```sh
git clone https://github.com/binbandit/riff.git
cd riff
```

### iPad and shared Swift code

On a Mac with Xcode and Swift 6.2 or later:

```sh
swift test
xcodebuild -project Riff.xcodeproj -scheme Riff -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Run `./scripts/build-ipad.sh` to create an unsigned device build at `artifacts/Riff-iPad-unsigned.ipa`. Installing it on a physical iPad requires signing.

### Windows companion

On Windows with the .NET 10 SDK:

```powershell
./scripts/build-windows.ps1
# For ARM PCs:
./scripts/build-windows.ps1 -Runtime win-arm64
```

The script runs core and Windows HTTPS integration tests, then creates a self-contained ZIP under `artifacts/`. Close any running companion before testing because the integration test uses the same port. ARM64 packages are cross-compiled; they still need a launch check on an ARM PC.

The core C# tests also run on macOS with the .NET 10 SDK:

```sh
dotnet test Companion/Riff.Tests
```

### Releases

The [Windows workflow](.github/workflows/companion.yml) tests and packages relevant pull requests. Relevant pushes to `main` publish a companion release after both Windows builds pass. iPad builds use a [separate workflow](.github/workflows/build.yml); iPad-only changes and README edits don't trigger companion releases.

Companion versions use tags such as `companion-v0.1.0`. Commit messages determine the version bump: `fix(companion): ...` bumps patch, `feat(companion): ...` bumps minor, and `!` or a `BREAKING CHANGE:` footer bumps major. Changed file paths determine which commits belong to a companion release. Other relevant changes bump patch.

The workflow generates release notes and changelogs from Git history. Use clear commit subjects, and let the workflow create version tags and changelogs.

## Contributing

[Issues](https://github.com/binbandit/riff/issues) and pull requests are welcome. For a bug, include your iPadOS and Windows versions, the companion version, what you expected, and the steps to reproduce it. Screenshots help with UI problems; leave pairing links and QR codes out of them.

For a larger change, open an issue first so we can talk through it. Keep pull requests focused, run the tests for the code you change, and say what you tested on real devices versus a simulator. If you have an iPad and Windows PC, working through the [device checks](docs/VERIFICATION.md) is a useful way to help.

Dependency licenses and notices are listed in [THIRD-PARTY.md](docs/THIRD-PARTY.md).
