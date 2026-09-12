import SwiftUI

struct ActionFields: View {
    @Environment(RiffStore.self) private var store
    let kind: String
    @State private var editingSound: Clip?
    @Binding var value: String
    var body: some View {
        switch kind {
        case "sound":
            NavigationLink {
                SoundPickerView(selection: $value)
            } label: {
                LabeledContent("Sound", value: store.snapshot.clips.first(where: { $0.id == value })?.name ?? "Choose a sound")
            }
            if let clip = store.snapshot.clips.first(where: { $0.id == value }) {
                Button("Edit sound", systemImage: "scissors") { editingSound = clip }
                    .sheet(item: $editingSound) { sound in
                        ExistingSoundEditorView(clip: sound) { saved in value = saved.id; editingSound = nil }
                    }
            }
            Text("Plays through the output selected in Audio settings. For game chat, choose your virtual cable.").font(.caption).foregroundStyle(.secondary)
        case "hotkey":
            TextField("Ctrl+Shift+M", text: $value).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("Use Ctrl, Alt, Shift, Win, letters, digits, F1-F24, or names like Space and Enter. The shortcut goes to the focused Windows app.").font(.caption).foregroundStyle(.secondary)
        case "text":
            TextField("Text to type", text: $value, axis: .vertical).lineLimit(3...6)
            Text("Types into the focused field on your PC. Add an Enter shortcut as the next sequence step if you want to send it.").font(.caption).foregroundStyle(.secondary)
        case "url": TextField("https://example.com", text: $value).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        case "app":
            if store.snapshot.apps.isEmpty { Text("On your PC, open Riff > Allowed apps and add an application first.").font(.subheadline).foregroundStyle(.secondary) }
            else { Picker("Application", selection: $value) { ForEach(store.snapshot.apps) { Text($0.name).tag($0.id) } } }
        case "media":
            Picker("Control", selection: $value) {
                Text("Play / pause").tag("playPause"); Text("Next track").tag("next"); Text("Previous track").tag("previous")
                Text("Volume up").tag("volumeUp"); Text("Volume down").tag("volumeDown"); Text("Mute / unmute").tag("mute")
            }
        case "deck":
            Picker("Open deck", selection: $value) {
                ForEach(store.snapshot.decks) { Text($0.name).tag($0.id) }
            }
            Text("Group related controls in another deck, then open it with one tap. Add a Go back button there to return.").font(.caption).foregroundStyle(.secondary)
        case "back":
            Text("Returns to the deck you opened this one from. Choosing a deck from the menu starts a new navigation path.").font(.caption).foregroundStyle(.secondary)
        case "stop":
            Text("Stops all Riff sounds and cancels remaining sequence steps. Works even while another action is running.").font(.caption).foregroundStyle(.secondary)
        default: EmptyView()
        }
    }
}
