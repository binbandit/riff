import SwiftUI

struct CompanionUpdatesView: View {
    @Environment(RiffStore.self) private var store
#if DEBUG
    @State private var previewChangelog = false
#endif
    var body: some View {
        Form {
            Section("Windows companion") {
                LabeledContent(store.connected ? "Installed version" : "Last connected version", value: store.snapshot.companionVersion ?? "Not reported")
                if let release = store.updates.release {
                    LabeledContent("Latest release", value: release.tag_name)
                    if release.isNewer(than: store.snapshot.companionVersion) {
                        Label("An update is available", systemImage: "arrow.down.circle.fill").foregroundStyle(Palette.accent)
                    } else if let version = store.snapshot.companionVersion, ReleaseVersion(version) != nil {
                        Text("No newer Windows version was found in the last check.").foregroundStyle(.secondary)
                    }
                } else if store.updates.checkedAt != nil {
                    Text("No public Windows release is available yet.").foregroundStyle(.secondary)
                }
                if (store.paired || !store.snapshot.computerName.isEmpty) && store.snapshot.companionVersion.flatMap(ReleaseVersion.init) == nil {
                    Text("This companion doesn’t report a readable version. Install a current release on Windows to enable version comparison.").font(.subheadline).foregroundStyle(.secondary)
                }
                if !store.connected { Text("Connect your PC to verify the version currently running.").font(.subheadline).foregroundStyle(.secondary) }
            }
            if let release = store.updates.release {
                Section {
                    NavigationLink { CompanionChangelogView(release: release) } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("What’s new")
                                Text("Latest companion features and fixes").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "sparkles") }
                    }
                }
            }
            Section {
                Link("View GitHub release", destination: store.updates.release?.page ?? GitHubRelease.releasesPage)
                ShareLink(item: store.updates.release?.page ?? GitHubRelease.releasesPage) { Label("Share release link", systemImage: "square.and.arrow.up") }
            }
            Section {
                Button {
                    Task { await store.updates.check(force: true) }
                } label: {
                    HStack { Label("Check for updates", systemImage: "arrow.clockwise"); Spacer(); if store.updates.checking { ProgressView() } }
                }.disabled(store.updates.checking)
                if let checked = store.updates.checkedAt {
                    LabeledContent("Last checked") { Text(checked, format: .dateTime.month().day().hour().minute()).foregroundStyle(.secondary) }
                }
                if let failure = store.updates.failure { Text(failure).foregroundStyle(.secondary) }
            } footer: {
                Text("Riff checks GitHub for stable Windows releases every six hours while the app is open and paired. No PC address, pairing key, or sound data is sent to GitHub.")
            }
            Section("Install on your PC") {
                Text("1. Open the release page on your Windows PC and download the Windows ZIP.")
                Text("2. Quit Riff from its system tray menu, then extract the ZIP into a new folder.")
                Text("3. Run the new Riff.Companion.exe. Your saved decks, sounds, and pairing stay on the PC.")
            }
        }
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden).background(Palette.background)
        .navigationTitle("Companion updates").navigationBarTitleDisplayMode(.inline)
        .task {
#if DEBUG
            await store.updates.check(force: ["changelog", "markdown"].contains(DesignPreview.screen))
#else
            await store.updates.check()
#endif
        }
#if DEBUG
        .navigationDestination(isPresented: $previewChangelog) {
            if let release = store.updates.release { CompanionChangelogView(release: release) }
        }
        .onChange(of: store.updates.release?.changelogKey, initial: true) { _, key in
            if ["changelog", "markdown"].contains(DesignPreview.screen), key != nil { previewChangelog = true }
        }
#endif
    }
}
