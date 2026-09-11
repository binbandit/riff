import SwiftUI

struct AudioSetupView: View {
    @Environment(RiffStore.self) private var store
    @State private var includeMicrophone = true

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Your voice. Your sounds.", systemImage: "mic.badge.plus")
                        .font(.title2.bold())
                    Text("Keep talking while your soundboard plays. A mixer on your PC combines both into the microphone your game hears.")
                        .foregroundStyle(.secondary)
                }.padding(.vertical, 8)
                Picker("Send to game chat", selection: $includeMicrophone) {
                    Text("My mic + sounds").tag(true)
                    Text("Just sounds").tag(false)
                }.pickerStyle(.segmented)
            } footer: {
                Text("These steps guide your Windows setup. Riff does not install drivers or change your game’s microphone for you.")
            }

            if includeMicrophone { microphoneSteps } else { cableSteps }

            Section("Try it before joining") {
                AudioSetupStep(number: 1, title: "Open your chat app’s mic test", detail: "Use headphones. Keep the game and other players’ voices playing directly through your headphones, outside the mixer.")
                AudioSetupStep(number: 2, title: includeMicrophone ? "Talk, then tap a sound" : "Tap a sound", detail: includeMicrophone ? "Confirm that your voice and the clip are both audible together. Lower the soundboard volume if it covers your voice." : "Confirm the clip is audible in the microphone test.")
                if store.connected, let clip = store.snapshot.clips.first {
                    Button {
                        Task { await store.preview(clip) }
                    } label: {
                        Label("Test with \(clip.name)", systemImage: "play.circle")
                    }
                    Button("Stop Riff sounds", systemImage: "stop.circle") {
                        Task { await store.stopAll() }
                    }
                }
                Text("Tests play through Riff’s saved PC output. Stop Riff sounds only stops the soundboard; it does not mute your microphone or music.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                DisclosureGroup("If sounds are quiet or cut off") {
                    Text("Use voice activation, or hold your game’s push-to-talk key for the whole clip. Riff does not press that key for you.")
                    Text("In your chat app, check the input threshold and try lowering noise suppression or automatic voice processing. Start at a low volume and retest.")
                }
                NavigationLink {
                    MusicSetupView()
                } label: { Label("Add music to your setup", systemImage: "music.note") }
            }
        }
        .scrollContentBackground(.hidden).background(Palette.background)
        .navigationTitle("Game chat setup").navigationBarTitleDisplayMode(.inline)
    }

    private var microphoneSteps: some View {
        Section {
            AudioSetupStep(number: 1, title: "Install Voicemeeter Standard", detail: "Download it on your PC, install, then restart Windows. This setup uses its built-in virtual audio devices; no separate cable is needed.")
            Link("Get Voicemeeter Standard", destination: URL(string: "https://vb-audio.com/Voicemeeter/")!)
            AudioSetupStep(number: 2, title: "Connect your headphones and mic", detail: "In Voicemeeter, set hardware output A1 to your headphones and the first hardware input to your regular microphone.")
            AudioSetupStep(number: 3, title: "Send Riff into the mixer", detail: "In Riff’s Sound controls, choose Voicemeeter Input (VB-Audio Voicemeeter VAIO), then tap Apply.")
            AudioSetupStep(number: 4, title: "Choose what everyone hears", detail: "On the microphone strip, turn B on and A off. On the virtual input strip, turn A and B on. A is what you hear; B is what your game hears.")
            AudioSetupStep(number: 5, title: "Choose the mixed microphone", detail: "In your game or Discord, select Voicemeeter Out B1 as the input. Older versions call it Voicemeeter Output. Leave the game’s output set to your headphones.")
            Text("Keep Voicemeeter running while you play. To mute your voice alone, use the microphone strip’s Mute button or your microphone’s physical mute.")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("On your Windows PC") } footer: {
            Text("Voicemeeter Standard is separate donationware. It is free to use; its maker asks you to pay a license amount if you find it useful or use it professionally. Paid extensions are not needed for this setup.")
        }
    }

    private var cableSteps: some View {
        Section {
            AudioSetupStep(number: 1, title: "Install VB-CABLE", detail: "Download the basic VB-CABLE package on your PC, install, then restart Windows.")
            Link("Get VB-CABLE", destination: URL(string: "https://vb-audio.com/Cable/")!)
            AudioSetupStep(number: 2, title: "Send Riff into the cable", detail: "In Riff’s Sound controls, choose CABLE Input, then tap Apply.")
            AudioSetupStep(number: 3, title: "Make the cable your microphone", detail: "Select CABLE Output as the input in your game or Discord. Keep your headphones as the game’s output.")
            Text("This route sends clips alone. Choose My mic + sounds above to keep your regular microphone in the mix.")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("On your Windows PC") } footer: {
            Text("VB-CABLE is separate donationware. Additional A/B or C/D cable packs are paid downloads and are not needed here.")
        }
    }
}

private struct AudioSetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number.formatted())
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Palette.accent)
                .frame(width: 28, height: 28)
                .background(Palette.accent.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct MusicSetupView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Keep your music close", systemImage: "music.note")
                        .font(.title2.bold())
                    Text("Play Apple Music on your Windows PC while you use Riff on your iPad. Apple Music’s streaming catalog needs a subscription.")
                        .foregroundStyle(.secondary)
                }.padding(.vertical, 8)
                Link("Apple Music for Windows setup", destination: URL(string: "https://support.apple.com/guide/music-windows/mus19e7bc658/windows")!)
            } footer: {
                Text("Riff does not yet browse your Apple Music library or relay Apple Music audio from your iPad to your PC. Subscription songs cannot be imported as Riff sound clips.")
            }

            Section("Listen while you play") {
                Text("Start your playlist in Apple Music on Windows and send it directly to your headphones. Your music stays separate from the microphone mix.")
                Text("Riff’s Media control buttons send Windows play/pause and track commands. They need Desktop automation enabled on the companion and a player that responds to media keys. They control the active player, not a specific Apple Music account.")
                Text("Soundboard-only mode disables these buttons. Use the player’s own controls to keep that mode on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Music in the microphone mix") {
                Text("For music you have permission to share, first complete My mic + sounds setup. Keep Apple Music listening private unless your use is permitted by the service and content rights.")
                AudioSetupStep(number: 1, title: "Choose just the music app", detail: "In Windows Settings → System → Sound → Volume mixer, find your playing music app under Apps. Set its output to Voicemeeter Input.")
                AudioSetupStep(number: 2, title: "Balance it against your voice", detail: "With A and B enabled on Voicemeeter’s virtual input, the music and Riff clips reach both your headphones and game chat. Lower music in its own player so your voice stays clear.")
                AudioSetupStep(number: 3, title: "Keep other players out of the mix", detail: "Leave Windows’ default output, the game and Discord on your headphones. Pause music in its player to stop sharing it; Riff’s Stop button only stops Riff clips.")
            }

            Section {
                DisclosureGroup("Official setup guides") {
                    Link("Voicemeeter inputs and outputs", destination: URL(string: "https://voicemeeter.com/quick-tips-voicemeeter-virtual-inputs-and-outputs-windows-10-and-up/")!)
                    Link("Windows per-app audio output", destination: URL(string: "https://support.microsoft.com/en-us/windows/hardware/audio/fix-app-audio-not-working-while-system-sounds-work-in-windows")!)
                    Link("Apple Media Services terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/")!)
                }
            }
        }
        .scrollContentBackground(.hidden).background(Palette.background)
        .navigationTitle("Music with Riff").navigationBarTitleDisplayMode(.inline)
    }
}
