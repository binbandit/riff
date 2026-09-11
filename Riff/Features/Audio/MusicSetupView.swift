import SwiftUI

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
