import SwiftUI
import AVFoundation

struct SoundPacksView: View {
    @Environment(RiffStore.self) private var store
    var onAdded: () -> Void
    @State private var packs: [SoundPack] = []
    @State private var failure: String?
    @State private var search = ""
#if DEBUG
    @State private var showPreviewDetail = false
#endif
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find your next reaction.").font(.system(.title, design: .rounded, weight: .bold))
                    Text("Recognizable memes, streamer favorites, and montage staples. Every sound is included on this iPad.")
                        .foregroundStyle(.secondary)
                }.padding(.vertical, 6)
                if let failure { Text(failure).foregroundStyle(.red) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    ForEach(packs.filter { $0.matches(search) }) { pack in
                        NavigationLink {
                            SoundPackDetailView(pack: pack, onAdded: onAdded)
                        } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: pack.icon).font(.title2).foregroundStyle(pack.tint)
                                        .frame(width: 52, height: 52).background(pack.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                                Text(pack.name).font(.title3.weight(.bold)).foregroundStyle(.primary)
                                Text(pack.description).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Text(pack.sounds.prefix(3).map(\.name).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                HStack {
                                    Text("\(pack.sounds.count) sounds · On this iPad")
                                    Spacer()
                                    if store.installingPackID == pack.id { ProgressView() }
                                    else if pack.installed(in: store.snapshot.clips).count == pack.sounds.count {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Added to PC")
                                    } else { Image(systemName: "ipad.landscape").foregroundStyle(pack.tint) }
                                }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            }.padding(20).frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
                                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain)
                    }
                }
                if !packs.isEmpty && packs.filter({ $0.matches(search) }).isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                Text("Preview every sound offline on this iPad. Add a pack to your paired PC to use it in your decks.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.background(Palette.background)
            .navigationTitle("Sound packs").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Find a pack or meme")
            .task {
                do { packs = try SoundPacks.load() } catch { failure = error.localizedDescription }
#if DEBUG
                showPreviewDetail = DesignPreview.screen == "pack-detail"
#endif
            }
#if DEBUG
            .navigationDestination(isPresented: $showPreviewDetail) {
                if let pack = packs.first(where: { $0.id == "epic-fails" }) { SoundPackDetailView(pack: pack, onAdded: onAdded) }
            }
#endif
    }
}

struct SoundPackDetailView: View {
    @Environment(RiffStore.self) private var store
    let pack: SoundPack
    let onAdded: () -> Void
    @State private var preview = PackPreview()
    @State private var adding = false
    @State private var added = false
    private var installed: [Clip] { pack.installed(in: store.snapshot.clips) }
    private var complete: Bool { installed.count == pack.sounds.count }
    private var installing: Bool { store.installingPackID == pack.id }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        Image(systemName: pack.icon).font(.title).foregroundStyle(pack.tint)
                            .frame(width: 60, height: 60).background(pack.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pack.name).font(.system(.title2, design: .rounded, weight: .bold))
                            Text("\(pack.sounds.count) sounds · On this iPad")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Text(pack.description).font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }.listRowBackground(Color.clear)
            Section {
                ForEach(pack.sounds) { sound in
                    HStack(spacing: 14) {
                        Button { preview.toggle(sound) } label: {
                            Image(systemName: preview.playingID == sound.id ? "stop.fill" : "play.fill")
                                .frame(width: 44, height: 44).foregroundStyle(pack.tint)
                                .background(pack.tint.opacity(0.10), in: Circle())
                        }.buttonStyle(.borderless)
                            .accessibilityLabel(preview.playingID == sound.id ? "Stop \(sound.name)" : "Preview \(sound.name) on iPad")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sound.name).font(.body.weight(.medium))
                            Text(String(format: "%.1f sec", sound.duration)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if installed.contains(where: { $0.id == sound.clipID }) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Added to PC")
                        }
                        Menu {
                            Link("Open original on \(sound.provider)", destination: sound.sourceURL)
                            Text("Uploaded by \(sound.uploader)")
                        } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }
                            .accessibilityLabel("Source for \(sound.name)")
                    }.padding(.vertical, 4)
                }
            } header: { Text("In this pack") } footer: {
                Text("Every sound is included on this iPad. Original source details are available beside each sound.")
            }
            if let error = preview.error { Section { Text(error).foregroundStyle(.red) } }
            if let error = store.packInstallError { Section { Text(error).foregroundStyle(.red) } }
        }
        .listSectionSpacing(16)
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollContentBackground(.hidden).background(Palette.background)
        .navigationTitle("Sound pack").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                HStack {
                    Label("Previews play on iPad", systemImage: "ipad.landscape").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop preview") { preview.stop() }.font(.caption).disabled(preview.playingID == nil)
                }
                if installing {
                    ProgressView(value: Double(store.packInstallProgress), total: Double(pack.sounds.count))
                    HStack {
                        Text(store.packInstallStatus).font(.caption).lineLimit(2)
                        Spacer()
                        Button("Pause") { store.cancelPackInstall() }.font(.subheadline)
                    }
                } else if complete {
                    Button { preview.stop(); adding = true } label: {
                        Label("Add pack to deck", systemImage: "plus.square.on.square").frame(maxWidth: .infinity)
                    }.buttonStyle(AccentButtonStyle()).disabled(!store.connected || store.busy)
                    Text("Added to PC · \(installed.count) sounds").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button { preview.stop(); store.installPack(pack) } label: {
                        Label(installed.isEmpty ? "Add to PC" : "Continue adding to PC · \(installed.count)/\(pack.sounds.count)", systemImage: "desktopcomputer")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(AccentButtonStyle()).disabled(!store.connected || !store.supportsPacks || store.busy)
                }
                if !store.connected { Text("Connect your PC to add packs and buttons.").font(.caption).foregroundStyle(.secondary) }
                else if !store.supportsPacks { Text("Update the Windows companion to add sound packs.").font(.caption).foregroundStyle(.secondary) }
                else if store.busy && !installing { Text("Wait for the current transfer or change to finish.").font(.caption).foregroundStyle(.secondary) }
            }.padding(20).background(.regularMaterial)
        }
        .sheet(isPresented: $adding, onDismiss: { if added { onAdded() } }) {
            AddSoundsView(clipIDs: installed.map(\.id), suggestedName: pack.name) { added = true }
        }
        .onDisappear { preview.stop() }
    }
}

private extension SoundPack {
    var tint: Color {
        switch color { case "purple": .purple; case "green": .green; case "pink": .pink; case "blue": .blue; default: Palette.accent }
    }
}

@MainActor @Observable final class PackPreview: NSObject, AVAudioPlayerDelegate {
    var playingID: String?
    var error: String?
    private var player: AVAudioPlayer?
    func toggle(_ sound: PackSound) {
        let wasSelected = playingID == sound.id
        stop(); error = nil
        guard !wasSelected else { return }
        do {
            let url = try SoundPacks.audioURL(for: sound)
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
            next.delegate = self; next.volume = 0.65
            guard next.play() else { throw RiffError.message("This preview could not be played.") }
            player = next; playingID = sound.id
        } catch { self.error = error.localizedDescription }
    }
    func stop() { player?.stop(); player = nil; playingID = nil }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if self.player === player { self.playingID = nil; self.player = nil } }
    }
}
