# Bundled sound pack audio

All 138 pack MP3s live in [`../Riff/Resources/PackSounds`](../Riff/Resources/PackSounds) and ship inside both applications. The shared catalog is [`../Riff/Resources/sound-packs.json`](../Riff/Resources/sound-packs.json); each `fileName` identifies a local resource. No audio is fetched from GitHub or source sites at runtime.

Keep audio and catalog changes together. Filenames contain the sound ID and complete SHA-256, and the companion validates both the expected byte count and hash when populating its library. Existing clip IDs remain stable so library renames and deck assignments survive the switch to bundled audio. The PC populates its library from its own bundled MP3s. No pack installation or transfer is needed, and deletions persist across restarts.

Original source pages, providers, and upstream download URLs remain in the catalog as attribution. The two 101soundboards recordings were supplied by the user, preserving their exact bytes. These third-party recordings are not covered by Riff's application code license; see [research and attribution](../docs/SOUND-PACKS.md).

The 36 communication clips come from Coqui Voice Pack v2 (MIT) and Kenney Voiceover Pack (CC0), converted to mono MP3 with consistent loudness. Their notices are included in `VoicePack-LICENSES.txt` alongside the audio and copied into the Windows companion’s `licenses` folder.

Lobby Jukebox adds 16 music excerpts, with original sources and audio processing recorded per clip in the catalog. Music clips are level-matched and have a short end fade; Social Credit Music remains unchanged in Montage Memes.

`swift test --filter SoundPackTests` checks every bundled resource's size, hash, and audio decoding without an internet connection.
