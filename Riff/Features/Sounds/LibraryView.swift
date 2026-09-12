import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(RiffStore.self) private var store
    var onAssign: (Clip) -> Void
    var onAdded: () -> Void
    @State private var showPacks = false
    @State private var selecting = false
    @State private var selectedIDs: [String] = []
    @State private var addingSounds = false
    @State private var addedSounds = false
    @State private var search = ""
    @State private var scope = SoundScope.all
    @State private var importing = false
    @State private var recording = false
    @State private var naming: SoundNameTarget?
    @State private var failure: String?
    @State private var deleteClip: Clip?
    @State private var recorded: Clip?
    private var clips: [Clip] { SoundCatalog.visible(store.snapshot.clips, query: search, scope: scope, favorites: store.favoriteClipIDs, deck: store.selectedDeck) }
    var body: some View {
        List {
            if !selecting {
                Section {
                    Button { showPacks = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Explore sound packs").font(.headline).foregroundStyle(.primary)
                                Text("Streamer favorites & meme classics. Included on this iPad.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }.buttonStyle(.plain)
                }
            }
            Section {
                Picker("Show sounds", selection: $scope) {
                    ForEach(SoundScope.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).listRowBackground(Color.clear)
                if selecting {
                    HStack(spacing: 16) {
                        Text("\(selectedIDs.count) selected").foregroundStyle(.secondary)
                        Spacer()
                        Button("Select shown") {
                            selectedIDs += clips.map(\.id).filter { !selectedIDs.contains($0) }
                        }.disabled(clips.isEmpty || Set(selectedIDs).union(clips.map(\.id)).count > 48 || clips.allSatisfy { selectedIDs.contains($0.id) })
                        Button("Clear") { selectedIDs.removeAll() }.disabled(selectedIDs.isEmpty)
                    }.font(.subheadline).buttonStyle(.borderless).listRowBackground(Color.clear)
                }
            }
            if !store.connected && !selecting {
                Section { Text("Preview sounds here. Connect your PC to record, import, or add them to a deck.").font(.subheadline).foregroundStyle(.secondary) }
            }
            Section {
                ForEach(clips) { clip in
                    HStack(spacing: 14) {
                        Button { Task { await store.preview(clip) } } label: {
                            Image(systemName: "play.fill").font(.body).foregroundStyle(Palette.accent)
                                .frame(width: 48, height: 48).background(Palette.accent.opacity(0.09), in: Circle())
                        }.buttonStyle(.borderless).accessibilityLabel("Play \(clip.name)")
                        if selecting {
                            Button { toggleSelection(clip) } label: {
                                HStack {
                                    soundName(clip)
                                    Spacer()
                                    Image(systemName: selectedIDs.contains(clip.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).foregroundStyle(selectedIDs.contains(clip.id) ? Palette.accent : .secondary)
                                }.contentShape(Rectangle()).frame(minHeight: 48)
                            }.buttonStyle(.plain)
                                .disabled(selectedIDs.count >= 48 && !selectedIDs.contains(clip.id))
                                .accessibilityLabel("Select \(clip.name)")
                                .accessibilityAddTraits(selectedIDs.contains(clip.id) ? .isSelected : [])
                        } else {
                            soundName(clip)
                            Spacer()
                            Button { onAssign(clip) } label: { Image(systemName: "plus.circle.fill").font(.title2).padding(8) }
                                .buttonStyle(.borderless).disabled(!store.connected).accessibilityLabel("Add \(clip.name) to deck")
                        }
                    }.padding(.vertical, 6)
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) { deleteClip = clip }.disabled(!store.connected)
                            Button("Rename") { naming = .existing(clip) }.tint(Palette.accent).disabled(!store.connected)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { store.toggleFavorite(clip) } label: {
                                Label(store.favoriteClipIDs.contains(clip.id) ? "Unfavorite" : "Favorite", systemImage: "star")
                            }.tint(Palette.accent)
                        }
                        .contextMenu {
                            Button(store.favoriteClipIDs.contains(clip.id) ? "Remove favorite" : "Add to favorites", systemImage: "star") { store.toggleFavorite(clip) }
                            Button("Rename sound", systemImage: "pencil") { naming = .existing(clip) }.disabled(!store.connected)
                            Button("Delete sound", role: .destructive) { deleteClip = clip }.disabled(!store.connected)
                        }
                }
            } header: { Text("\(clips.count) sounds") }
            if clips.isEmpty {
                SoundEmptyView(scope: scope, searching: !search.isEmpty).listRowBackground(Color.clear)
            }

        }
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden).background(Palette.background)
        .searchable(text: $search, prompt: "Find a sound")
        .navigationDestination(isPresented: $showPacks) { SoundPacksView(onAdded: onAdded) }
#if DEBUG
        .task {
            if ["packs", "pack-detail"].contains(DesignPreview.screen) { showPacks = true }
            if DesignPreview.screen == "sound-selection" || DesignPreview.screen == "add-sounds" {
                selecting = true; selectedIDs = Array(store.snapshot.clips.prefix(3).map(\.id))
                if DesignPreview.screen == "add-sounds" { addingSounds = true }
            }
            if DesignPreview.screen == "rename", let clip = store.snapshot.clips.first { naming = .existing(clip) }
            if DesignPreview.screen == "import", let url = Bundle.main.url(forResource: "level-up", withExtension: "wav") { naming = .imported(url) }
        }
#endif
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if selecting {
                    Button { addingSounds = true } label: {
                        Label(selectedIDs.isEmpty ? "Select sounds to continue" : "Add \(selectedIDs.count) to deck", systemImage: "plus.square.on.square")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(AccentButtonStyle()).disabled(selectedIDs.isEmpty)
                        .padding(.horizontal, 20).padding(.top, 12)
                }
                SoundPreviewBar()
            }.background(.regularMaterial)
        }
        .sheet(isPresented: $addingSounds, onDismiss: {
            if addedSounds { addedSounds = false; selecting = false; selectedIDs.removeAll(); onAdded() }
        }) {
            AddSoundsView(clipIDs: selectedIDs) { addedSounds = true }
        }
        .onChange(of: store.snapshot.clips.map(\.id)) { _, ids in
            selectedIDs.removeAll { !ids.contains($0) }
        }
        .toolbar {
            if selecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { selecting = false; selectedIDs.removeAll() }
                        .accessibilityLabel("Cancel sound selection")
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select") { selecting = true; selectedIDs.removeAll() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Record sound", systemImage: "mic") { recording = true }
                        Button("Import audio", systemImage: "folder") { importing = true }
                    } label: { Image(systemName: "plus") }.disabled(!store.connected).accessibilityLabel("Add sound")
                }
            }
        }
        .sheet(isPresented: $recording, onDismiss: { if let recorded { self.recorded = nil; onAssign(recorded) } }) {
            RecordingView { clip in recorded = clip; recording = false }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.wav, .mp3, .mpeg4Audio, .aiff, UTType(filenameExtension: "aac") ?? .audio]) { result in
            switch result {
            case .success(let url): naming = .imported(url)
            case .failure(let error): failure = error.localizedDescription
            }
        }
        .sheet(item: $naming, onDismiss: {
            if let recorded { self.recorded = nil; onAssign(recorded) }
        }) { target in
            switch target {
            case .imported(let url):
                NavigationStack {
                    ClipEditorView(url: url, name: target.name) { clip in recorded = clip; naming = nil }
                }
            case .existing(let clip):
                SoundNameEditor(name: clip.name) { name in try await store.renameClip(clip, name: name) }
            }
        }

        .alert("Couldn’t open sound", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }

        .confirmationDialog("Delete \(deleteClip?.name ?? "sound")?", isPresented: Binding(get: { deleteClip != nil }, set: { if !$0 { deleteClip = nil } }), titleVisibility: .visible) {
            Button("Delete sound", role: .destructive) {
                if let clip = deleteClip { Task { await store.deleteClip(clip) } }; deleteClip = nil
            }
        } message: { Text("Remove this sound from any buttons before deleting it.") }
    }
    private func toggleSelection(_ clip: Clip) {
        if selectedIDs.contains(clip.id) { selectedIDs.removeAll { $0 == clip.id } }
        else if selectedIDs.count < 48 { selectedIDs.append(clip.id) }
    }
    private func soundName(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(clip.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                if store.favoriteClipIDs.contains(clip.id) {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(Palette.accent).accessibilityLabel("Favorite")
                }
            }
            Text(String(format: "%.1f sec", clip.duration)).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
