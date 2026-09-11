import SwiftUI

enum SoundNameTarget: Identifiable {
    case imported(URL)
    case existing(Clip)
    var id: String {
        switch self { case .imported(let url): url.absoluteString; case .existing(let clip): clip.id }
    }
    var name: String {
        switch self {
        case .imported(let url): String(url.deletingPathExtension().lastPathComponent.prefix(60))
        case .existing(let clip): clip.name
        }
    }
}

struct SoundNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    let save: (String) async throws -> Void
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var focused: Bool
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sound name", text: $name).focused($focused).submitLabel(.done)
                        .onSubmit { if valid { submit() } }
                    Text("\(trimmed.utf16.count)/60").font(.caption).foregroundStyle(trimmed.utf16.count > 60 ? .red : .secondary)
                } header: { Text("Name your sound") } footer: {
                    Text("This changes the library name. Your buttons keep their own names and still play the same sound.")
                }
                if saving { HStack { ProgressView(); Text("Saving name…") } }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Rename sound").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { submit() }.fontWeight(.semibold).disabled(!valid)
                }
            }
            .onAppear { focused = true }
        }.interactiveDismissDisabled(saving)
    }
    private var valid: Bool { !saving && !trimmed.isEmpty && trimmed.utf16.count <= 60 }
    private func submit() {
        saving = true; failure = nil; focused = false
        Task {
            do { try await save(trimmed); dismiss() }
            catch { failure = error.localizedDescription }
            saving = false
        }
    }
}
