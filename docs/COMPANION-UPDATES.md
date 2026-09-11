# Companion update checks

The iPad checks the public [Riff GitHub releases](https://github.com/binbandit/riff/releases) while it is open and paired. A notice above the deck appears when the connected Windows companion reports an older version. Tap it for release details and installation steps. **Settings → Companion updates** also offers **Check for updates**, the installed and available versions, the last successful check, and a shareable release link.

Checks do not interrupt playback. Successful results, including an empty release list, are cached on the iPad for six hours. Failed automatic checks wait at least 15 minutes before retrying; a manual check can retry immediately. Offline errors retain the last successfully checked release and show a separate error. The app does not claim an unverified version is up to date. Old companions without version reporting show a version-check notice once a release is available, with instructions to install a current companion.

These are in-app notices while Riff is open, not background push notifications. Installation is performed on Windows: quit Riff from its tray menu, extract the release ZIP into a new folder, and run the new executable. Decks, clips, and pairing remain in the Windows user's existing Riff data folder.

## Release integration

The workflow is maintained separately. The application recognizes its current conventions:

- Stable tags: `companion-v0.1.0` and subsequent semantic versions.
- Windows assets: `Riff-0.1.0-win-x64.zip` or `Riff-0.1.0-win-arm64.zip`, matching the tag's version, with an uploaded state and a nonzero size.
- Legacy stable `v1.0.0` tags with `Riff-win-x64.zip` or `Riff-win-arm64.zip` are also supported.
- Drafts, prereleases, malformed versions, and releases containing only iPad downloads do not trigger Windows updates.
- The app selects the highest stable companion version, regardless of release-list ordering. If that version has no ready Windows ZIP, it reports the incomplete release instead of claiming an older download is current.

Windows publishes stamp the executable through MSBuild's `Version` property, such as `-p:Version=0.1.0`. The companion exposes its assembly informational version (without commit metadata) as the optional `companionVersion` field in authenticated `/api/state` responses. Direct local builds default to `0.0.0-dev`; a release build's supplied version takes precedence. The version also appears in the Windows window title. State format versioning is independent of application versioning.

The GitHub client uses a separate, unauthenticated HTTPS session. It sends no pairing token, local PC address, sound data, or deck content. It requests release pages in batches of 100, up to 10 pages, and reports an error if it cannot examine the complete history. Release links are constructed under the fixed Riff repository using validated tags, not URLs supplied by a companion or release notes. GitHub's endpoint behavior is documented in the [official Releases API](https://docs.github.com/en/rest/releases/releases).

## Verification

- 36 Swift tests passed, including numeric and prerelease ordering, unknown installed versions, versioned Windows assets, independent iPad releases, incomplete uploads, paginated histories, GitHub errors, persistent caching, retry timing, concurrent checks, and older snapshot decoding.
- 25 Windows core tests passed. The companion and Windows HTTPS integration-test project compiled with zero warnings/errors. The integration assertion checks that `/api/state` reports the running assembly version; execution of that test still requires Windows.
- iPad simulator and unsigned device Release builds passed. The simulator's update screen queried the real public GitHub API and displayed the empty-release state. No release had been published at the time of the check. Update-available decisions were tested with fixtures, not represented as a real connected PC.
- Physical follow-up: connect an older companion, publish a newer stable release with its Windows ZIP, manually check, open/share the release link, update Windows, and confirm the notice disappears after the PC reconnects. Also check loss of internet while local soundboard playback continues.
