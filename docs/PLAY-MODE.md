# Play mode and pages

Tap the Play mode icon beside Sounds to give the deck more room. The deck selector, audio output, playback mode and Stop all remain available. Tap the collapse icon to return to editing and recording. Playing sounds continue when you change modes or decks.

In Play mode, long-press editing and drag-to-rearrange are unavailable. Tap the deck name to switch decks. Steam-linked automatic switching still works; opening audio controls or the deck picker temporarily pauses it as usual.

## Multiple pages

A deck holds up to 48 buttons. Grid size determines how many fit on each page. Add more sounds from the library and Riff creates additional pages automatically without removing any buttons.

- Swipe across the board or use the left and right arrows.
- Tap the page count to jump directly to any page. Each entry shows that page's first button.
- Switching decks remembers your place during the current app session.
- Changing grid size keeps the previous page's first button in view where possible. If buttons are removed, the selected page is clamped to the remaining pages.

Use separate named decks for different collections or games. Pages are portions of a deck, not independently named collections.

## Soundboard mode on Windows

Play mode changes the iPad interface. Windows Soundboard mode separately blocks all desktop automation, including media keys, keyboard shortcuts and sequences. A locked pad explains how the PC setting works when tapped. This is a reduction in automation risk, not a guarantee of game or anti-cheat approval. See [game compatibility](GAME-COMPATIBILITY.md).

## Verification

The integrated Swift package passed 55 tests, including page bounds, per-deck navigation, grid changes, and old/new companion payloads. The simulator and unsigned iPad device builds passed. Actual iPad simulator captures cover Play mode with three pages, dark appearance selection, and microphone setup.

The simulator's Device Hub computer-use connection timed out, so captures use DEBUG launch fixtures and are not a claim of successful tap-through automation. Real Windows microphone mixing and game-chat playback still require device testing.

## Simulator captures

- [Play mode](screenshots/ipad-play-mode.png)
- [Three-page preview](screenshots/ipad-play-pages.png)
- [Appearance in light colours](screenshots/ipad-appearance-light.png)
- [Appearance in dark colours](screenshots/ipad-appearance-dark.png)
- [Live microphone setup](screenshots/ipad-audio-setup.png)
