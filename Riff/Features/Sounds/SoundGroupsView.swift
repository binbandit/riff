import SwiftUI

struct SoundGroupsView<Row: View>: View {
    let clips: [Clip]
    let expandedResults: Bool
    @ViewBuilder let row: (Clip) -> Row
    @State private var expanded: Set<String> = ["personal"]

    var body: some View {
        ForEach(SoundCatalog.groups(clips)) { group in
            Section {
                if !expandedResults {
                    Button {
                        if !expanded.insert(group.id).inserted { expanded.remove(group.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: group.icon).foregroundStyle(Palette.accent).frame(width: 28)
                            Text(group.name).font(.headline).foregroundStyle(.primary)
                            Spacer()
                            Text("\(group.clips.count)").foregroundStyle(.secondary).monospacedDigit()
                            Image(systemName: expanded.contains(group.id) ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(group.name), \(group.clips.count) sounds")
                        .accessibilityValue(expanded.contains(group.id) ? "Expanded" : "Collapsed")
                        .accessibilityHint("Double tap to \(expanded.contains(group.id) ? "collapse" : "expand")")
                }
                if expandedResults || expanded.contains(group.id) {
                    ForEach(group.clips) { clip in row(clip) }
                }
            } header: {
                if expandedResults { Text(group.name) }
            }
        }
    }
}
