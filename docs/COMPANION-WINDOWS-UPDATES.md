# Updates and release notes on Windows

The companion's **Updates** tab checks the public GitHub releases on startup and every six hours while Riff remains open. **Check for updates** refreshes immediately. An **Updates · New** tab label appears when a newer stable Windows build is available. The panel shows both the installed build and latest release, distinguishes development builds ahead of the stable release, and explains failed checks without claiming the app is current.

**Open downloads on GitHub** opens the verified repository's release page. Riff does not download or execute an update automatically. Quit the old companion before extracting and running a new version. Saved decks and clips remain in `%LOCALAPPDATA%\Riff`.

The client checks up to ten pages of 100 releases, orders stable versions semantically, and ignores draft, prerelease, and iPad-only releases. A newer companion tag whose Windows assets are still pending produces an explicit message rather than incorrectly claiming that an older version is latest. Checks use a separate unauthenticated HTTP client, not iPad pairing credentials. Requests time out and have byte limits. Failed checks leave any previously loaded release information visible during the current session.

**What's new** downloads the published `CHANGELOG.md` asset through GitHub's public asset API. Markdig parses Markdown into a native, selectable rich-text view: headings, emphasis, strikethrough, code, links, nested lists, task checkboxes, quotes, and tables. HTML is omitted and images show their alternative text; no scripts or remote images run in the companion. Only HTTP(S) links can open from release notes. The renderer's bundled BSD license is available from the panel.

## Verification

The portable companion suite passed 53 tests, including semantic version ordering, draft/prerelease filtering, pending assets, pagination, public asset headers without authorization, oversized/invalid UTF-8 notes, and parsed Markdown formatting and link restrictions. The Windows companion and Windows test project cross-compiled with zero warnings and errors. A Windows-only acceptance test loads rendered Markdown into an actual RichTextBox and checks visible content plus bold/italic formatting; execution requires Windows and was not run on the development Mac.

A live public GitHub check on September 12, 2026 retrieved `companion-v0.1.1`, its `CHANGELOG.md` asset `557381511`, and rendered all 671 characters into native RTF. This validates the live request path. Visual Windows UI inspection, link interaction, and installation remain physical Windows checks.
