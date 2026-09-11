# Downloadable sound pack audio

These MP3s are the optional pack downloads. This folder sits outside the iPad and Windows app targets, so these recordings do **not** increase either app's download size or install automatically.

The shared catalog is [`../Riff/Resources/sound-packs.json`](../Riff/Resources/sound-packs.json). Each entry points to this public repository through `raw.githubusercontent.com/binbandit/riff/main/sound-packs/audio/`. The filenames contain the sound ID and complete SHA-256; both apps validate the expected size and hash before accepting a download.

Commit the audio files together with the catalog. The URLs become available after those files reach `main`; local files or an unmerged branch do not make the public URLs live. Keep previously published files at their existing paths so older app versions continue to work. When replacing a recording, add a new file with its new hash and update the catalog instead of overwriting the old file. These small MP3s are ordinary Git files, not Git LFS pointers.

Original source pages and providers remain in the catalog. `originalDownloadURL` records the upstream file when available. The two 101soundboards recordings were downloaded from the requested pages by the user and supplied as local MP3s, preserving their exact bytes. The source sites are not contacted when using packs.

These third-party recordings are not covered by any license for Riff's application code. Redistribution and broadcast rights have not been verified. See [research and attribution](../docs/SOUND-PACKS.md).

`swift test --filter SoundPackTests` checks the catalog against every local audio file. After publication, `RIFF_TEST_PACK_DOWNLOADS=1 swift test --filter SoundPackTests` also verifies every public GitHub download through the app's downloader.
