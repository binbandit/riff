import SwiftUI

struct AISettingsView: View {
    @Environment(RiffStore.self) private var store
    @State private var key = ""
    @State private var failure: String?
    var body: some View {
        Form {
            Section {
                Label(store.hasDeviceAIKey ? "Ready on this iPad" : "Suggestions without a PC", systemImage: "sparkles")
                Text("Get button labels, icons, colors, and starter decks directly from your iPad. Only an internet connection is needed.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                SecureField(store.hasDeviceAIKey ? "Replace OpenAI API key" : "OpenAI API key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(store.hasDeviceAIKey ? "Update key" : "Enable suggestions") {
                    do { try store.saveAIKey(key); key = ""; failure = nil }
                    catch { failure = error.localizedDescription }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if store.hasDeviceAIKey {
                    Button("Remove key from this iPad", role: .destructive) {
                        do { try store.removeAIKey(); key = ""; failure = nil }
                        catch { failure = error.localizedDescription }
                    }
                }
                if let failure { Text(failure).font(.footnote).foregroundStyle(.red) }
                Link("Get an OpenAI API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
            } header: { Text("Your OpenAI account") } footer: {
                Text("Your key is stored in this iPad’s Keychain and sent only to OpenAI. API usage is billed separately to your OpenAI account and requires access to GPT-5.6 Luna.")
            }
            Section {
                Text("Suggestions send relevant sound, game, app, and button names, your descriptions, and selected action details to OpenAI. Audio files and pairing details stay on your devices. Website credentials and query strings are removed. Your manual edits are kept, and suggestions never run actions.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("What is shared") }
            if !store.hasDeviceAIKey {
                Section {
                    Text("If you already enabled AI on your Windows companion, Riff can use it while connected. Add a key here to use suggestions independently.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden).background(Palette.background)
        .navigationTitle("AI suggestions").navigationBarTitleDisplayMode(.inline)
        .onDisappear { key = "" }
    }
}

struct AISetupLink: View {
    @State private var showingSetup = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set up AI on this iPad. No PC connection needed.").font(.caption).foregroundStyle(.secondary)
            Button("Set up AI suggestions", systemImage: "sparkles") { showingSetup = true }
        }
        .sheet(isPresented: $showingSetup) {
            NavigationStack {
                AISettingsView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSetup = false } } }
            }
        }
    }
}
