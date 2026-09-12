# Bundled sound pack audio

All 35 pack MP3s live in [`../Riff/Resources/PackSounds`](../Riff/Resources/PackSounds) and ship inside the iPad app. The shared catalog is [`../Riff/Resources/sound-packs.json`](../Riff/Resources/sound-packs.json); each `fileName` identifies a local resource. No audio is fetched from GitHub or source sites at runtime.

Keep audio and catalog changes together. Filenames contain the sound ID and complete SHA-256, and transfers validate both the expected byte count and hash. Existing clip IDs remain stable so library renames and deck assignments survive the switch to bundled audio. The paired PC receives files over the local connection and stores normalized WAVs for playback.

Original source pages, providers, and upstream download URLs remain in the catalog as attribution. The two 101soundboards recordings were supplied by the user, preserving their exact bytes. These third-party recordings are not covered by Riff's application code license; see [research and attribution](../docs/SOUND-PACKS.md).

`swift test --filter SoundPackTests` checks every bundled resource's size, hash, and audio decoding without an internet connection.
