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
