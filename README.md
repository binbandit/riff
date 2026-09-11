# Riff

Your iPad, your control room. A native SwiftUI control deck and a Windows 11 companion, with no account or subscription.

## What you can do

- Tap large color-coded pads to play sounds on your PC.
- Record up to 60 seconds on the iPad, listen back, name the clip, and turn it into a button.
- Import WAV, MP3, M4A, AAC or AIFF audio (20 MB / 60 seconds maximum), on iPad or PC.
- Send clips into game voice chat using a virtual microphone.
- Create, rename, duplicate, and delete decks. Drag buttons to rearrange them in Edit mode. The long-press menu also offers Move earlier/later.
- Choose 3, 4, or 5 columns; compact windows use two columns.
- Link decks to Steam games and optionally switch when Steam reports a game running.
- Assign keyboard shortcuts, typed text, media controls, websites, locally approved applications, or sequences of up to 20 actions.
- Stop all playing sounds and cancel remaining sequence steps immediately.

Six original synthesized sounds are included. Sound effects can overlap, with up to 16 playing at once. The iPad stays awake while Riff is in the foreground. Without a PC connection, the starter sounds can be previewed on the iPad; PC actions and editing require a connection.

This implements common control-deck actions. It does not run Elgato plugins or provide every proprietary Stream Deck integration. OBS and other apps can be controlled through their configured keyboard shortcuts; a dedicated OBS API integration is not included.

## Install on Windows 11

1. Extract `Riff-win-x64.zip`, keeping the `Sounds` folder beside `Riff.Companion.exe`.
2. Run `Riff.Companion.exe`. The package includes .NET, so no separate runtime is needed.
3. Allow Riff through Windows Firewall on **Private** networks.
4. In **Connect iPad**, select your PC's home Wi-Fi/Ethernet address. Use this address rather than a VPN address.
5. Leave the companion running. Closing its window minimizes it to the system tray; use the tray's **Quit Riff** command to exit.

This personal build is unsigned. ARM Windows users can build a `win-arm64` package with the script below. No driver is installed by Riff.

If no firewall prompt appears, use Windows Security to allow the executable on private networks. Alternatively, the optional `scripts/allow-private-network.ps1` can create a rule restricted to this executable, TCP port 49321, private networks, and the local subnet. Run it in an administrator PowerShell and pass the full executable path. Do not open this port on your router.

## Install on your iPad

### From your Windows PC

The provided `Riff-iPad-unsigned.ipa` is a device build that needs signing with your own Apple account before installation.

1. Download [Sideloadly for Windows from its official site](https://sideloadly.io/) and follow its current requirements for Apple device drivers.
2. Connect your iPad by USB, unlock it, and trust your PC.
3. Open Sideloadly, select your iPad, and load `Riff-iPad-unsigned.ipa`.
4. Complete signing locally using your own Apple account, then install. Do not share your password or verification codes in this repository or chat.
5. Follow the iPad prompts to trust your development app and enable Developer Mode if requested. Open Riff and allow local-network access.

Sideloadly is a separate third-party tool. Its physical installation flow has not been tested in this workspace. Its [official FAQ](https://sideloadly.io/faq) documents free signing and the seven-day renewal requirement; its auto-refresh feature can help with renewals while your devices are reachable. No paid Stream Deck software is involved.

### From a Mac with Xcode

The native app must be signed for your device. The project targets iPadOS 17 or later, including the current iPadOS, and uses Swift 6.2-era build features. Use Xcode 26 or newer; this workspace was built with Xcode 27.

1. On your Mac, open `Riff.xcodeproj` in Xcode.
2. In the Riff target's **Signing & Capabilities**, choose your own Apple development team. Change the bundle identifier if Xcode requests a unique identifier.
3. Connect your iPad, trust the Mac, and enable Developer Mode when requested.
4. Select your iPad as the run destination and run the app.
5. Allow local-network access. Microphone and camera permission are requested only when you record or scan a pairing code.

A free Apple Personal Team can install the app for personal testing, but its provisioning profiles expire after **7 days**, requiring signing/installation again (or a sideloading refresh). A paid developer account is not required for this personal testing route. This is an Apple distribution restriction, not a Riff subscription. See [Apple's account comparison](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Pair the devices

Put the iPad and PC on the same trusted local network. In Riff on iPad, tap **Connect your PC**, scan the companion's QR code, then tap **Connect PC**. If scanning is unavailable, transfer the pairing link privately and paste it.

The link contains your PC address, a random access key, and a certificate fingerprint. HTTPS is pinned to that fingerprint, including self-signed certificates. The iPad stores pairing in Keychain; Windows protects its identity and key using the current user's Windows data protection. No account, cloud relay, or internet access is required after installation.

If your PC's IP address changes, scan a new link. **Revoke paired devices** on Windows invalidates old pairing links. Pairing gives your iPad control of the PC, so keep the link and QR code private. Avoid guest Wi-Fi with client isolation.

## Play soundboard clips as your voice

The complete route is:

**iPad button → Riff on Windows → CABLE Input → CABLE Output → game microphone input**

1. Install [VB-CABLE](https://vb-audio.com/Cable/) on Windows and restart. It is an optional donationware virtual audio driver, installed separately.
2. In Riff's audio settings, choose **CABLE Input** as the sound output and apply.
3. In the game or Discord, choose **CABLE Output** as the microphone/input device.
4. Start the chat app's microphone test and play a Riff sound.
5. Use voice activation, or hold the game's push-to-talk key for the duration of the clip. Riff currently sends shortcut taps, not held push-to-talk keys.

If a clip is cut off, adjust the game's voice threshold and turn off noise suppression, echo cancellation, or automatic voice processing as needed. Games may intentionally process or filter non-speech audio.

To monitor the sounds in your headphones, use **Windows Sound → More sound settings → Recording → CABLE Output → Properties → Listen**, enable **Listen to this device**, and select your headphones. This monitoring path can add latency. Riff has one selected playback output, not a built-in mixer. Use an optional mixer such as [Voicemeeter](https://vb-audio.com/Voicemeeter/) if you want to combine your real microphone with the clips.

The audio test plays through the selected PC output. If it is a virtual cable, you will see it in your chat app's microphone test, rather than hear it through speakers unless monitoring is enabled. Apply output changes before testing; stop existing clips before changing output.

## Game-specific layouts

Create or duplicate a deck, choose **Deck settings**, and link a Steam game. Enable **Follow my Steam game** in Settings. Installed game names are read from Steam's local library manifests, and running state is read from Steam's local registry. No Steam password or Web API key is required.

Detection checks every few seconds while the iPad is active. Riff switches when a new linked game is detected. It pauses switching while editing or using sheets. Manual deck selection lasts until the next detected game change. If multiple games are running, no game is detected, or the game has no linked deck, the current deck stays selected. One deck can be linked to each game. Steam library names refresh about once a minute.

Steam's local registry format is not a stable public API, so detection is best effort and may need updating after Steam changes. A running game is not necessarily the foreground window. Non-Steam games use manual deck selection in this version.

## Other controls

- **Keyboard shortcut:** `Ctrl+Shift+M`, `Win+D`, `Win+Shift+S`, `F13`, and similar combinations. Input goes to the focused Windows app. Configure OBS hotkeys there, then assign matching Riff buttons.
- **Type text:** writes to the focused field. It does not press Enter automatically. A sequence can type text and then tap Enter.
- **Launch app:** first add the `.exe` under **Allowed apps** on Windows, then select it on iPad. Arbitrary shell commands and app paths are not accepted through the API.
- **Website:** opens an HTTP/HTTPS address in the PC's default browser.
- **Sequence:** ordered actions with a delay before each step; up to 20 steps and 30 seconds of total delays. Another action is rejected while a sequence is running. Stop All cancels the remaining steps, but cannot undo apps opened or text already typed.

Windows can block simulated input into elevated applications or protected games. See Microsoft's [SendInput restrictions](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput). The app does not bypass anti-cheat protection.

## Data and backups

Decks, sounds, output settings, and the app allowlist live in `%LOCALAPPDATA%\Riff`. Close Riff before backing up this folder. `state.json` is written atomically; clips are normalized to PCM WAV in `clips`. The iPad keeps a cached snapshot so it can display your decks while disconnected.

Windows pairing identity is protected for the current Windows user. For a new PC or Windows account, copy `state.json` and `clips` into a fresh Riff data folder, then pair again; do not copy the protected identity/key files. App paths and sound-device IDs may need updating on a different PC. A corrupt state file is reported at startup rather than silently overwritten.

## Build and test

Windows, with the .NET 10 SDK:

```powershell
./scripts/build-windows.ps1
# Optional ARM build:
./scripts/build-windows.ps1 -Runtime win-arm64
```

The script runs core tests and the Windows HTTPS integration test, then publishes a self-contained ZIP. Close the running companion before the Windows integration test because it uses the same local port.

On a Mac:

```sh
swift test
dotnet test Companion/Riff.Tests
xcodebuild -project Riff.xcodeproj -scheme Riff -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

`./scripts/build-ipad.sh` creates an unsigned device IPA on a Mac. GitHub Actions builds both applications, runs the platform-appropriate tests, and attaches the Windows ZIP and unsigned iPad IPA. Dependencies and notices are documented in [THIRD-PARTY.md](docs/THIRD-PARTY.md).

See [verification and device checks](docs/VERIFICATION.md) for what has been tested locally and the physical Windows/iPad checks still needed.
