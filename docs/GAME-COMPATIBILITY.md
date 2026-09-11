# Games, audio, and input automation

Riff starts in **Soundboard mode** on Windows, including when loading a saved configuration from an older version. Sound buttons, recording/imports, output selection, Riff's playback volume, and Stop all remain available. All non-sound buttons are rejected by the companion: keyboard shortcuts, typed text, media keys, app/website launches, and all sequences. Media buttons are included because the current implementation uses simulated keyboard input for them.

The Windows **Controls** tab is the only place to turn this mode off for desktop automation. The choice persists locally and is reported as `soundboardOnly` in the paired iPad snapshot, alongside `soundboard-only-v1`. Mode changes cancel pending sequence steps under the same lock that starts actions. The server rechecks the policy at execution, so an older client cannot bypass it. No remote mode-changing endpoint exists.

## What the companion does

- Plays audio through normal Windows audio output devices. A separately installed virtual audio cable can be selected as the game's microphone. Riff does not install a driver of its own.
- Reads Steam's local manifest files and running-game registry flags. This is best-effort discovery, not a supported stable Steam API, and does not open game processes or inspect their memory.
- Runs with an `asInvoker` manifest and `uiAccess=false`. It does not request administrator privileges, install game hooks, inject code, modify game files, or evade anti-cheat checks.
- With Soundboard mode disabled, sends desktop keyboard/text/media commands using Windows `SendInput`. This is input automation, not physical input. Failed or blocked input is reported, not worked around.

For voice chat, hold the physical push-to-talk key or use voice activation where the game permits it. Soundboard mode does not synthesize push-to-talk input.

## Why this is a reduction in risk, not a guarantee

Valve describes game modifications that provide an advantage as cheats, including changed executables and libraries. Its Counter-Strike input policy also restricts automation of multiple player actions, including hardware automation. Therefore, simply avoiding injection is insufficient: Riff disables its automation by default. See [Valve's VAC guidance](https://help.steampowered.com/en/faqs/view/571A-97DA-70E9-FF74) and [Counter-Strike's Side-stepping Skill announcement, August 19, 2024](https://store.steampowered.com/oldnews/?appgroupname=Counter-Strike%3A+Global+Offensive&appids=730&enddate=1725174000&feed=steam_community_announcements).

Microsoft documents `SendInput` as synthetic keyboard/mouse input and states that Windows integrity boundaries can block it. Riff respects those boundaries. See [Microsoft's SendInput documentation](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput).

BattlEye states that ordinary non-hack programs and passive non-cheating activity do not result in its bans. This is general guidance, not approval of Riff or every virtual audio driver. See [BattlEye support](https://www.battleye.com/support/).

No vendor has approved or certified Riff. We cannot guarantee immunity from anti-cheat actions or game/server moderation. Check each game's current third-party-tool and voice-chat rules, including sound spam and harassment rules. Do not enable desktop automation to gain a gameplay advantage or bypass a blocked input path.

## Verification

Portable core tests cover legacy-state defaults, persisted opt-in, and rejection of every non-sound action, including unknown action kinds. The Windows HTTPS integration test covers blocked requests from an authenticated client, persisted PC changes, and cancellation of a waiting text sequence across rapid mode changes. On macOS, the core suite passed and the companion plus Windows tests cross-compiled with no warnings; Windows integration execution and physical game/anti-cheat validation require Windows and have not been claimed here.
