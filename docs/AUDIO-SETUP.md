# Microphone, soundboard, and music

Riff sends clips to a Windows output and can also play a copy through your PC headphones. To use your regular microphone at the same time, combine both in a separate Windows audio mixer and choose its virtual output as the game's microphone. The iPad app includes these instructions under Sound controls → Microphone, sounds & music. This is guided setup, not automatic installation or a built-in microphone mixer.

## Hear your own sounds

In **Sound controls**, keep **Output** set to your chat cable or mixer. Enable **Hear sounds myself**, select your PC headphones, set **Headphone volume**, then **Apply**. These controls are also on the Windows companion's **Audio & voice chat** tab. The iPad controls require a companion with headphone monitoring support.

Your headphone volume is independent of the sound volume sent to chat. Both copies stop together, and queued sounds wait for both copies to finish. Selecting the same physical device for both outputs plays only one copy, using Sound volume. Choose an explicit headphone device if your PC default output is the virtual cable. Use **Stop all** before changing devices or turning monitoring on or off; sounds already playing or queued retain their routing.

If headphones disconnect, Riff keeps the chat output playing and reports the headphone problem in the Windows Activity tab. Reconnect them or select another headphone output. If Windows **Listen to this device** or Voicemeeter already sends the clips to your headphones, use only one monitoring route to avoid hearing a delayed duplicate. The Voicemeeter setup below already monitors through its A bus, so leave Riff's **Hear sounds myself** off for that setup.

## Your mic and Riff together

1. Install **Voicemeeter Standard** on Windows and restart. Standard includes the virtual devices this route needs; a separate VB-CABLE is unnecessary.
2. In Voicemeeter, choose headphones as hardware output **A1** and your microphone as the first hardware input.
3. In Riff's Sound controls, select **Voicemeeter Input (VB-Audio Voicemeeter VAIO)** and Apply.
4. On the microphone strip, enable **B**, disable **A**. On the virtual input strip, enable **A** and **B**. A lets you monitor clips; B sends the mix to chat. Leaving microphone A off avoids hearing your own delayed voice.
5. Select **Voicemeeter Out B1** as the game's input. Older drivers call it **Voicemeeter Output**. Keep Voicemeeter running while playing.

These settings use Standard's A/B buses. Banana uses A1/B1 labels instead. Device names vary across driver versions. See the [Voicemeeter Standard manual](https://vb-audio.com/Voicemeeter/Voicemeeter_UserManual.pdf) and [official device-name guide](https://voicemeeter.com/quick-tips-voicemeeter-virtual-inputs-and-outputs-windows-10-and-up/).

Keep Windows' default output, game audio, and incoming Discord voices routed directly to headphones. Sending incoming chat into the mixed microphone causes echo. Mute your voice with the microphone's own mute or its mixer strip. Riff's Stop button stops Riff clips only, not the microphone or an external music player.

Voicemeeter Standard is a separate donationware product. VB-Audio says it is free to use and asks users to pay for a license if useful or used professionally. Optional paid extensions are unnecessary for this route. It is not bundled with Riff. [Download and licensing](https://voicemeeter.com/).

## Clips without your live mic

The simpler route is **Riff → CABLE Input → CABLE Output → game microphone**. Install basic VB-CABLE, restart Windows, choose CABLE Input in Riff and Apply, then CABLE Output in the game's input settings. This does not combine your microphone with the clips. VB-CABLE is donationware; additional paid A/B or C/D cable packs are unnecessary. [Official VB-CABLE page](https://vb-audio.com/Cable/).

## Music

Install Apple Music on Windows and play there while using the iPad as the deck. Streaming catalog access requires an Apple Music subscription. The music can stay private in your headphones, alongside game audio. [Apple's Windows installation guide](https://support.apple.com/guide/music-windows/mus19e7bc658/windows), [subscription guide](https://support.apple.com/guide/music-windows/mus89c4e3d1a/windows).

For audio you are entitled to send into chat, Windows supports selecting a separate output per app: **Settings → System → Sound → Volume mixer → Apps → Output device**. With the app playing, choose Voicemeeter Input for that app. Keep the virtual input's A and B enabled and adjust music volume in the player. This routing is inferred from Windows' per-app output support and Voicemeeter's documented virtual input; it has not been tested on a physical Windows PC with Apple Music in this development environment. [Microsoft's output-device guide](https://support.microsoft.com/en-us/windows/hardware/audio/fix-app-audio-not-working-while-system-sounds-work-in-windows).

A streaming subscription does not grant unrestricted sharing or broadcast rights. Apple limits its media services to permitted personal uses and does not transfer the content owners' rights. The in-app guide separates private Apple Music listening from sharing music you have permission to use. [Apple Media Services terms](https://www.apple.com/legal/internet-services/itunes/).

Riff's existing Media control pads send Windows media keys. They require **Desktop automation** enabled on the companion, a player that handles those keys, and may affect another active player. They do not address a specific Apple Music account or playlist. Keep Soundboard-only mode enabled and use the music player's own controls when you want Riff to send no keyboard input.

### Current integration boundary

Riff has no Apple Music account connection, catalog browser, playlist launcher, or iPad-to-PC music relay. Subscription tracks are not soundboard import files. Apple documents MusicKit for authenticated playback through its player APIs and disallows uploading or modifying MusicKit content. A future integration could use authorized catalog browsing and official playback on the PC; MusicKit on iPad is not an API for exporting a protected stream into the companion. [MusicKit overview](https://developer.apple.com/musickit/), [MusicKit program terms, section 3.3.6 D](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/).

## Check the actual chat path

Use the game or chat app's microphone test first, with headphones and low volume. Confirm voice alone, a clip alone, then both at once. If a clip is cut off, inspect the chat app's input threshold and voice processing. Hold the game's push-to-talk key for the whole clip when using push-to-talk; Riff does not synthesize that hold.

Verify that other players' voices do not return into the mic, that stopping Riff leaves your live voice working, and that music pauses in its own player. Testing the selected output or seeing it listed in Riff does not prove the game's microphone is configured correctly.

Physical Windows audio, Apple Music media-key behavior, mixer latency, and game-lobby routing still need testing on the user's Windows hardware. No external audio products were installed or purchased as part of this change.
