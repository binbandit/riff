# Stream Deck feature comparison

Compared against Elgato's official documentation on 12 September 2026. Riff implements its own actions for an iPad and Windows PC; it does not load Elgato plugins or claim full Stream Deck compatibility.

| Stream Deck ability | Riff support |
| --- | --- |
| Soundboard, media controls, shortcuts, text, websites, app launch | Already supported. Apps must be approved in the Windows companion. |
| Profiles and pages | Decks with individual grid sizes, automatic pagination, duplication, and manual selection. |
| Multi Actions with delays | Action sequences with up to 20 steps, 0–5 seconds before each step, and 30 seconds of total delays. |
| Multi Action Switch / Hotkey Switch | **Added:** Action switch with independent first and second sequences. Use one shortcut per sequence for a hotkey switch. |
| Random Action | **Added:** One uniformly selected action from up to 20 choices per press. Repeats are possible. |
| Folder / profile navigation | **Added:** Open deck and Go back buttons, with a toolbar Back button. Uses existing decks as groups; this is not a separate nested-folder model. |
| Stop sound / cancel Multi Action | **Added:** Assign Stop all to any button. The existing toolbar control remains available. |
| Smart Profiles | **Added:** Link an approved Windows app to a deck and follow the focused application. Steam game following remains available. |
| Custom key appearance | Existing colors, symbols, and emoji. Custom image upload and animated key art are not implemented. |
| Pinned actions across pages | **Added:** Pin any button to the leading slots on every page, with overflow handling for small grids. |
| Key Logic (single / double / hold) | **Added:** Optional double-tap and hold actions alongside the normal tap. Secondary gestures support single actions, including navigation and Stop all. |
| Profile and action sharing | **Added:** Export/import Riff decks and individual buttons as .riff.json layouts. Review actions and relink sounds, apps, and deck targets. Audio files are not bundled. |
| Direct OBS, Discord, lighting, and other plugin integrations | Not implemented. Existing hotkeys can control applications that expose keyboard shortcuts. |
| Rotary dials, touch strips, plugin SDK / Marketplace | Not implemented. |

## Use the new actions

Update both the iPad app and Windows companion. In **Add button → Action**, choose **Action switch**, **Random action**, **Open deck**, **Go back**, or **Stop all**. The new choices only appear when the companion advertises support.

For a stream start/end button, choose **Action switch**, then configure the **First press** and **Second press** sequences. Each side supports the same actions as a normal sequence. The button's **1 / 2** badge indicates which sequence runs next, not the actual state of OBS or another application. Riff shares this state between connected iPads. Only a fully completed sequence advances the side. A cancelled or failed sequence keeps its side, although steps already executed cannot be undone. Editing the button or restarting the companion resets it to the first sequence.

For a group of controls, create a deck and add an **Open deck** button pointing to it. Return with the toolbar **Back** button or add a **Go back** button. Navigation also works with cached decks while offline. Selecting a different deck from the menu or an automatic switch starts a fresh navigation path. Remove links to a deck before deleting that deck.

For app profiles, add the executable under **Allowed apps** on Windows. Select it under **Deck settings → Follow your app**, then turn on **Settings → Follow my focused app**. Each app can be linked to one deck. The companion matches the foreground process's executable path to the approved app. Some packaged or protected apps may not expose a matching executable. Polling detects changes while Riff is open; this is not instantaneous. A linked focused app takes priority over a Steam game; when it loses focus, Steam following can resume. With neither a matching app nor game, Riff keeps the current deck. Manual deck choices remain until the detected context changes, and editing pauses automatic switching.

Soundboard mode permits sound, navigation, and Stop all buttons. Sequences, switches, and random actions still require desktop controls to be enabled on Windows, even when their individual steps only play sounds. Both sequence sides are validated, and sounds/apps used by either side cannot be deleted while referenced.

## One button, three gestures

In **Edit button**, enable **Double-tap** and/or **Hold** and choose the action for each. For example, tap to play/pause music, double-tap to skip, and hold to go to the previous track. Secondary gestures support sounds, shortcuts, text, websites, approved apps, media controls, Open deck, Go back, and Stop all. Sequences, action switches, and random actions remain available on the normal tap only.

A double-tap waits for the system's double-tap interval before deciding a single tap. Hold recognizes once after 0.55 seconds, with a 12-point movement allowance. Native gesture recognition makes the gestures mutually exclusive; moving to scroll cancels the pending gesture. Regular buttons keep their normal immediate taps. VoiceOver exposes named double-tap and hold actions without requiring those physical gestures.

The **2×** and hand badges identify configured gestures. A hold-bound button uses its hold to run the action; choose **Edit buttons** from the deck menu to edit it, then its context menu is available for sharing, pinning, or duplication. Sounds on a button share that button's playback and queue toggle: triggering a sound while that button is playing stops it. Use separate buttons when independent overlapping sound toggles are needed.

Gesture bindings are included in duplication, automatic offline syncing, and sharing. Layouts containing them use format 2 so older importers reject the file instead of silently discarding actions; ordinary layouts still use format 1. Linked sounds, apps, and decks are validated and relinked for every gesture. Windows resolves the stored gesture by button ID, rejects missing/unknown gestures, and applies Soundboard mode to the selected action. Soundboard mode can therefore allow a sound gesture while blocking a shortcut on the same button. Connected gestures require `key-logic-v1`; navigation and local sounds remain available offline.

## Share layouts and keep important buttons visible

Long-press a button and choose **Pin to every page**, or turn on **Pin to every page** in its editor. Pinned buttons appear first, in their deck order, on every page. Their pin setting is saved on Windows and shared with paired iPads. Each button still has one identity, so editing, playback state, and action-switch state stay consistent across pages. Reorder pinned buttons among themselves; unpin one to move it among ordinary buttons.

If the grid is too small for all the pins plus ordinary buttons, Riff keeps at least one slot for scrolling through the remaining buttons. Extra pinned buttons join the normal pages. In a 1×1 grid, every button appears on its own page. **Grid size** shows the resulting page count and how many pins repeat.

Open **… → Share & import layouts → Export deck** to save a `.riff.json` file. For a single button, long-press it and choose **Share button**. Exports work from cached layouts while offline. Exported files include names, icons, colors, pins, text, URLs, shortcuts, both sides of action switches, random choices, gesture bindings, and grid settings. They exclude pairing details, PC audio settings, approved executable paths, and audio files. Typed text and websites are included as configured, so review those when choosing what to share.

To import, choose a `.riff.json` file under **Share & import layouts**. Review the actions, choose a new or existing destination deck, and match its sounds, approved applications, and linked decks to resources on your PC. Unambiguous name matches are suggested. Duplicate names require an explicit choice. If a resource is missing, add it to the library or Allowed apps first. New deck imports restore the exported grid on this iPad; importing buttons into an existing deck preserves its grid and metadata. Automatic app/game links are left for you to configure.

Imports create new button identities and remap internal navigation. They never replace an existing deck. Edits are saved on the iPad and synced to Windows, which validates the complete edit with version checking. Failed syncs remain pending for retry. Retrying an interrupted save reuses the same import identities to prevent duplicate buttons. Layouts larger than 8 MB, unsupported formats/actions, inconsistent resource lists, duplicate IDs, and invalid sequence limits are rejected. Elgato `.streamDeckProfile` and `.streamDeckAction` files cannot be imported.

## Compatibility and verification

New model fields are optional. Existing saved decks remain readable, and the iPad omits absent fields when saving to older companions. New actions require the `deck-actions-v1` capability; app following requires `smart-profiles-v1`. Pins require `pinned-pads-v1`. Layout sharing uses the existing validated deck-save endpoint and checks the destination companion’s capabilities. As with other deck edits, the companion validates the complete layout and rejects stale version writes.

Tests cover switch alternation, failure, cancellation, state reset, random choice selection, action limits, navigation references, smart-profile links, older JSON, iPad navigation history, and automatic-switch precedence. iPad simulator and Windows cross-builds check compilation. Actual Windows foreground detection, simulated input, and multi-device live feedback still need physical-device verification.

Verification after the sharing and pinning additions: 110 Swift tests and 100 cross-platform companion tests passed. The iPad simulator build and Windows companion/integration-test builds succeeded. The import review, export picker, action editor, and pinned pages were visually checked in an iPad simulator. Tests cover resource remapping, switch-side preservation, malformed layouts, capacity limits, stable retry identities, sync failures, and pin reachability across grid sizes. Windows-only integration tests were compiled, not executed on this Mac.

Verification after Key Logic: 126 Swift tests and 108 cross-platform companion tests passed. The iPad simulator build and Windows companion/test cross-build passed. The editor and board were visually reviewed. Gesture selection, wire requests, capability gates, Soundboard policy, resource protection, format compatibility, and offline merging are covered by automated tests. Physical tap/double-tap/hold timing and scrolling cancellation still need device verification: the simulator UI-control connection was unavailable. Windows-only gesture cancellation tests were compiled, not executed on this Mac.

## Sources

- [Elgato Stream Deck overview: pages, folders, Smart Profiles, Multi Actions](https://www.elgato.com/us/en/explorer/products/stream-deck/what-is-a-stream-deck/)
- [Elgato Multi Actions](https://help.elgato.com/hc/en-us/articles/360027960912-Elgato-Stream-Deck-Multi-Actions)
- [Elgato software release notes: Multi Action Switch and Random Action](https://help.elgato.com/hc/de/articles/360028242631-Elgato-Stream-Deck-Software-Release-Notes)
- [Elgato Smart Profiles](https://help.elgato.com/hc/en-us/articles/360053419071-Elgato-Stream-Deck-Smart-Profiles)
- [Elgato profile capabilities and sharing](https://docs.elgato.com/stream-deck/profiles/getting-started/)
- [Elgato Stream Deck: Key Logic and software features](https://www.elgato.com/ww/en/p/stream-deck)

- [Elgato pinned actions and folders](https://help.elgato.com/hc/en-us/articles/26638431612429-Elgato-Stream-Deck-Pinned-Actions-and-Folders)
- [Elgato action sharing and resource relinking](https://help.elgato.com/hc/en-us/articles/29655138607505-Elgato-Stream-Deck-Action-Sharing)

- [Elgato: How to use Key Logic](https://www.elgato.com/us/en/explorer/products/stream-deck/key-logic-stream-deck/)
