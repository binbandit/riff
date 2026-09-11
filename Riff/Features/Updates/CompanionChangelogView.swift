import SwiftUI
import MarkdownUI

struct CompanionChangelogView: View {
    let release: GitHubRelease
    @State private var notes = ReleaseChangelogStore()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(releaseLabel).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                if notes.loading && displayedMarkdown == nil {
                    HStack(spacing: 12) { ProgressView(); Text("Loading what’s new…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
                if let markdown = displayedMarkdown {
                    ReleaseMarkdown(markdown: markdown, baseURL: release.page)
                }
                if let failure = notes.failure {
                    VStack(alignment: .leading, spacing: 12) {
                        if notes.markdown != nil { Label("Showing saved changelog", systemImage: "clock").font(.subheadline.weight(.medium)) }
                        Text(failure).foregroundStyle(.secondary)
                        Button("Try again", systemImage: "arrow.clockwise") { Task { await notes.load(release, force: true) } }.disabled(notes.loading)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
                }
                Link("View release on GitHub", destination: release.page).font(.subheadline)
            }
            .frame(maxWidth: 680, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle("What’s new").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await notes.load(release, force: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(notes.loading).accessibilityLabel("Refresh changelog")
            }
        }
        .task(id: release.changelogKey) {
#if DEBUG
            if DesignPreview.screen == "markdown" { return }
#endif
            await notes.load(release)
        }
    }
    private var displayedMarkdown: String? {
#if DEBUG
        if DesignPreview.screen == "markdown" { return DesignPreview.markdown }
#endif
        return notes.markdown
    }
    private var releaseLabel: String {
#if DEBUG
        if DesignPreview.screen == "markdown" { return "Formatting test, not release notes" }
#endif
        return release.tag_name
    }
}

struct ReleaseMarkdown: View {
    let markdown: String
    let baseURL: URL
    @ScaledMetric(relativeTo: .body) private var textSize = 17.0
    var body: some View {
        Markdown(MarkdownDisplay.hidingComments(in: markdown), baseURL: baseURL)
            .markdownTheme(.gitHub.text {
                FontSize(textSize)
                ForegroundColor(.primary)
                BackgroundColor(.clear)
            }.link { ForegroundColor(Palette.accent) })
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                ["https", "http"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
            })
    }
}
