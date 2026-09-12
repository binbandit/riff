# Verification

## Final local pass

The integrated working tree passed 59 Swift tests and 53 portable companion tests. The native iPad simulator build, unsigned iPad device Release build, and Windows x64 self-contained Release publish succeeded. Windows-only test projects compile; their tests require Windows and were not run on this Mac.

Meaningful regression checks in this pass:

- Reproduced audio draft loss through real simulator NavigationStack push/pop. Both audio screens now preserve output and volume across navigation and canceled pairing. All eight after-fix assertions passed. Temporary DEBUG instrumentation was removed.
- Reproduced a blank offline deck after the starter deck had been deleted. The actual store now selects an existing cached deck at startup.
- Reproduced an upload racing a held background poll using the real store and pinned HTTPS client against a loopback companion-state fixture. The new clip and authoritative version are available when upload returns; stale polls cannot overwrite them. If the follow-up state request fails after a successful upload, the app retains the saved clip and reconnects instead of requesting a duplicate upload. The fixture is not the Windows companion and does not execute actions.
- Reproduced invalid duplicated deck names containing emoji. Copies now fit Windows' UTF-16 name limit and retain their suffix and independent button identities.
- Windows regression cases cover pending release assets, missing changelogs, retry recovery, repeated update-view disposal, and repeated server shutdown. They compile but still need execution on Windows. Temporary-file cleanup cannot hold the import gate or turn a saved clip into an apparent failed upload; HTTP shutdown runs even when audio cleanup fails.

Previously verified locally: certificate pinning and redirect rejection over loopback HTTPS; deck rules and stale-write checks; clip selection/export with real PCM samples; soundboard playback policy and real bundled-audio simulator smoke checks; release version comparison and bounded changelog downloads; native Markdown rendering; theme persistence/contrast; page navigation and capacity changes.

## Visual and interaction coverage

Actual simulator captures cover the main board, Play mode, a three-page DEBUG preview, light/dark theme selection, library selection, grid settings, recording/trimming, microphone setup, and rendered release Markdown. See [Play mode](screenshots/ipad-play-mode.png), [appearance](screenshots/ipad-appearance-dark.png), and [microphone setup](screenshots/ipad-audio-setup.png).

Device Hub computer-use attachment has timed out. Screenshots and the explicit lifecycle fixtures above are not a claim of a complete computer-use tap-through test. Physical vibration was not tested: iPad touchscreens do not provide iPhone-style vibration. Native feedback requests are paired with visual press feedback and may be ignored on unsupported hardware. See [touch feedback](HAPTICS.md).

Xcode's only build warning is skipped App Intents metadata extraction because Riff does not use AppIntents.

## Required Windows and physical-iPad checks

1. Run `dotnet test Companion/Riff.WindowsTests -c Release` with the ordinary companion closed. Check startup, closing to tray, reopening, and quitting at normal and enlarged Windows display scaling.
2. Sign and install the iPad app, pair by QR code, relaunch both apps, and verify reconnection. Test revoked pairing and a Wi-Fi interruption. Actions must not replay after reconnecting.
3. Play, overlap, toggle-stop, replace, preview, and Stop all on actual Windows output devices. Unplug an active output and verify subsequent playback recovers.
4. Record/import, trim, preview privately on iPad, save, assign, rename, and delete sounds. Add multiple sounds and rearrange/copy buttons. Reopen both apps to verify persistence.
5. Use the chat app's microphone test to verify clips alone, then live microphone plus clips through the optional mixer. Test voice activation/push-to-talk and noise processing. Keep game/chat playback outside the microphone mix. See [audio setup](AUDIO-SETUP.md).
6. Confirm Soundboard mode blocks every desktop action and sequence while sounds remain usable. Only opt into desktop automation for allowed uses. No game or anti-cheat vendor has approved Riff; see [game compatibility](GAME-COMPATIBILITY.md).
7. Test Steam-linked switching, manual deck selection, multi-page swipes/direct jumps, portrait/landscape, small windows, VoiceOver, larger text, and Reduce Motion. Judge tactile feedback only on supported hardware.
8. In the Windows Updates tab, test offline retry, a newer release, readable Markdown, friendly hyperlinks, and the GitHub download link. Test the equivalent iPad release screen.

## Build and feature limits

The iPad IPA is unsigned and requires signing before installation. The Windows preview is a development build, not a published release. Cross-compilation does not validate physical audio, Windows input permissions, firewall reachability, or anti-cheat compatibility.

Riff uses a selected sound output and an optional headphone output. Live-mic mixing and music routing use a separately installed Windows mixer. Apple Music catalog browsing and iPad-to-PC music relay are not implemented. The iPad app must remain open as a control surface. Push-to-talk is held physically. Steam detection reads local data and is best effort. Riff does not implement Elgato plugins or a dedicated OBS API client.


## Headphone monitoring

The headphone settings request first failed against the original audio contract because it accepted only one output. After adding monitoring, the isolated headphone-monitoring change passed 71 Swift tests and 77 portable companion tests. The iPad simulator build and Windows companion/test-project builds succeeded. New checks cover the real iPad store over loopback HTTPS, compatibility with an older companion that rejects unknown fields, independently saved headphone volume, settings persistence, disconnected headphones, and invalid volumes. Windows HTTPS integration coverage for headphone settings compiles but has not been run on this Mac.

The [headphone controls capture](screenshots/ipad-headphone-controls.png) is a native iPad simulator layout check using temporary sample output devices. The sample state and launch instrumentation were removed after capture. Device Hub computer-use attachment timed out, so this does not claim a full UI tap-through or a physical listening test.

Still requires a Windows PC with two audio endpoints: select CABLE Input and headphones, enable Hear sounds myself, and test a clip in both headphones and the chat app's microphone test. Confirm independent volume, toggle/Stop all, Overlap/One at a time/Queue, same-device deduplication (including PC default), restart persistence, and headphone unplug/reconnect without interrupting chat playback. Disable any existing Windows or mixer monitoring for this check.
