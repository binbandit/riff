import SwiftUI

struct PadAppearanceEditor: View {
    @Binding var pad: Pad
    private let emojiGroups: [(name: String, items: [String])] = [
        ("Reactions", ["😂", "🤣", "😭", "😎", "🥹", "😍", "🤩", "😇", "😴", "🤔", "🙃", "😬", "😱", "🤯", "🥳", "💀", "👀", "🫡", "🤡", "👻"]),
        ("Good vibes", ["✨", "🔥", "❤️", "🎉", "🎊", "👏", "🙌", "👍", "👎", "👋", "🤝", "💪", "💯", "💸", "🏆", "👑"]),
        ("Sounds & music", ["🎵", "🎶", "🎧", "🎤", "🎙️", "📻", "🔊", "🔇", "🔔", "🥁", "🎸", "🎹", "🎺", "🚨", "⏰", "💥"]),
        ("Play & explore", ["🎮", "🕹️", "🎲", "🎯", "🎬", "🍿", "☕", "🍕", "🚀", "🛸", "✈️", "🛫", "🛬", "🚁", "🏎️", "⚡", "🌈", "🌙", "☀️", "🌊"])
    ]
    private let icons = ["sparkles", "waveform", "theatermasks", "hand.raised", "timer", "circle.circle", "light.beacon.max", "gamecontroller", "bolt", "heart", "star", "speaker.wave.2", "mic", "playpause", "forward.end", "command", "desktopcomputer", "viewfinder", "text.bubble", "globe", "app", "square.stack.3d.up", "speaker.slash", "flame", "airplane", "airplane.departure", "airplane.arrival", "antenna.radiowaves.left.and.right", "face.smiling"]
    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        Form {
            Section {
                HStack { Spacer(); PadTile(pad: pad).frame(width: 150, height: 150).disabled(true); Spacer() }
                    .listRowBackground(Color.clear)
            }
            Section("Color") {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Palette.colors, id: \.self) { color in
                        Button { pad.color = color } label: {
                            Circle().fill(Palette.color(color)).frame(width: 32, height: 32)
                                .overlay {
                                    if pad.color == color {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Palette.ink)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(color.capitalized) button color")
                            .accessibilityAddTraits(pad.color == color ? .isSelected : [])
                    }
                }.padding(.vertical, 5)
            }
            Section("Emoji") {
                ForEach(emojiGroups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.name).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(group.items, id: \.self) { item in
                                Button { pad.icon = "emoji:" + item } label: {
                                    Text(item).font(.title).frame(maxWidth: .infinity, minHeight: 44)
                                        .background(pad.icon == "emoji:" + item ? pad.tint.opacity(0.24) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay {
                                            if pad.icon == "emoji:" + item {
                                                RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent, lineWidth: 2)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel(item)
                                    .accessibilityAddTraits(pad.icon == "emoji:" + item ? .isSelected : [])
                            }
                        }
                    }.padding(.vertical, 8)
                }
            }
            Section("Symbols") {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(icons, id: \.self) { icon in
                        Button { pad.icon = icon } label: {
                            Image(systemName: icon).font(.system(size: 20)).frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(pad.icon == icon ? Palette.accent : .secondary)
                                .background(pad.icon == icon ? pad.tint.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(pad.icon == icon ? .isSelected : [])
                    }
                }.padding(.vertical, 8)
            }
        }.scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Icon & color").navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: pad.icon)
            .sensoryFeedback(.selection, trigger: pad.color)
    }
}
