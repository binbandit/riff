import SwiftUI

struct PadAppearanceEditor: View {
    @Binding var pad: Pad
    private let emoji = ["✨", "😂", "😭", "😎", "💀", "👀", "🫡", "🤡", "🔥", "❤️", "🎉", "💸", "🚨", "⏰", "👏", "🎮", "✈️", "🛫", "🛬", "🚁", "📻"]
    private let icons = ["sparkles", "waveform", "theatermasks", "hand.raised", "timer", "circle.circle", "light.beacon.max", "gamecontroller", "bolt", "heart", "star", "speaker.wave.2", "mic", "playpause", "forward.end", "command", "desktopcomputer", "viewfinder", "text.bubble", "globe", "app", "square.stack.3d.up", "speaker.slash", "flame", "airplane", "airplane.departure", "airplane.arrival", "antenna.radiowaves.left.and.right", "face.smiling"]
    var body: some View {
        Form {
            Section {
                HStack { Spacer(); PadTile(pad: pad).frame(width: 150, height: 150).disabled(true); Spacer() }
                    .listRowBackground(Color.clear)
            }
            Section("Icon & color") {
                    HStack(spacing: 18) {
                        ForEach(Palette.colors, id: \.self) { color in
                            Button { pad.color = color } label: {
                                Circle().fill(Palette.color(color)).frame(width: 32, height: 32)
                                    .overlay { if pad.color == color { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Palette.ink) } }
                            }.buttonStyle(.plain).accessibilityLabel("\(color) button color").accessibilityAddTraits(pad.color == color ? .isSelected : [])
                        }
                    }.padding(.vertical, 5)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 10) {
                        ForEach(emoji, id: \.self) { item in
                            Button { pad.icon = "emoji:" + item } label: {
                                Text(item).font(.title).frame(width: 42, height: 44)
                                    .background(pad.icon == "emoji:" + item ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).accessibilityLabel(item)
                        }
                    }.padding(.vertical, 8)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 14) {
                        ForEach(icons, id: \.self) { icon in
                            Button { pad.icon = icon } label: {
                                Image(systemName: icon).font(.system(size: 20)).frame(width: 40, height: 40)
                                    .foregroundStyle(pad.icon == icon ? Palette.accent : .secondary)
                                    .background(pad.icon == icon ? pad.tint.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
                        }
                    }.padding(.vertical, 8)
            }
        }.scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Icon & color").navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: pad.icon)
            .sensoryFeedback(.selection, trigger: pad.color)
    }
}
