import SwiftUI

struct SoundPickerView: View {
    @Environment(RiffStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var query = ""
    @State private var scope = SoundScope.all
    private var clips: [Clip] {
        SoundCatalog.visible(store.snapshot.clips, query: query, scope: scope, favorites: store.favoriteClipIDs, deck: store.selectedDeck)
    }
    var body: some View {
        List {
            Section {
                Picker("Show sounds", selection: $scope) {
                    ForEach(SoundScope.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).listRowBackground(Color.clear)
            }
            ForEach(clips) { clip in
                HStack(spacing: 12) {
                    Button { Task { await store.preview(clip) } } label: {
                        Image(systemName: "play.fill").frame(width: 44, height: 44)
                            .background(Palette.accent.opacity(0.09), in: Circle())
                    }.buttonStyle(.borderless).accessibilityLabel("Preview \(clip.name)")
                    Button {
                        selection = clip.id; dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(clip.name).foregroundStyle(.primary)
                                Text(String(format: "%.1f sec", clip.duration)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection == clip.id { Image(systemName: "checkmark").fontWeight(.semibold) }
                        }.padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.borderless)
                        .accessibilityLabel("Choose \(clip.name)").accessibilityAddTraits(selection == clip.id ? .isSelected : [])
                    Button { store.toggleFavorite(clip) } label: {
                        Image(systemName: store.favoriteClipIDs.contains(clip.id) ? "star.fill" : "star")
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.borderless)
                        .accessibilityLabel("\(store.favoriteClipIDs.contains(clip.id) ? "Unfavorite" : "Favorite") \(clip.name)")
                }
            }
            if clips.isEmpty { SoundEmptyView(scope: scope, searching: !query.isEmpty).listRowBackground(Color.clear) }
        }
        .searchable(text: $query, prompt: "Find a sound")
        .scrollContentBackground(.hidden).background(Palette.background)
        .navigationTitle("Choose a sound").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { SoundPreviewBar() }
    }
}

struct SoundEmptyView: View {
    let scope: SoundScope
    let searching: Bool
    var body: some View {
        if searching { ContentUnavailableView.search }
        else {
            ContentUnavailableView {
                Label(scope == .favorites ? "Your favorites go here" : scope == .deck ? "No sounds on this deck yet" : "Add your first sound", systemImage: scope == .favorites ? "star" : "waveform")
            } description: {
                Text(scope == .favorites ? "In All, swipe a sound right or hold it to add a favorite. Favorites are saved on this iPad." : scope == .deck ? "Sounds used by this deck’s buttons and sequences appear here." : "Record a snippet or import an audio file to get started.")
            }
        }
    }
}

struct SoundPreviewBar: View {
    @Environment(RiffStore.self) private var store
    var body: some View {
        HStack(spacing: 16) {
            Label(store.connected ? "Previews play through \(store.outputName)" : "Previews play on this iPad", systemImage: store.cableSelected && store.connected ? "mic" : "speaker.wave.2")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
            Button { Task { await store.stopAll() } } label: {
                Label("Stop all", systemImage: "stop.fill").font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }
        }.padding(.horizontal, 20).padding(.vertical, 8).background(.regularMaterial)
    }
}
