import SwiftUI

struct PadReordering: ViewModifier {
    let enabled: Bool
    let id: String
    let move: (String) -> Void
    func body(content: Content) -> some View {
        if enabled {
            content.draggable(id).dropDestination(for: String.self) { ids, _ in
                guard let source = ids.first, source != id else { return false }
                move(source); return true
            }
        } else { content }
    }
}

struct PadTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tapFeedback = 0
    let pad: Pad
    var editing = false
    var active = false
    var playing = false
    var blocked = false
    var action: () -> Void = {}
    private var theme: AppTheme { ThemePreferences.shared.theme }
    private var foreground: Color { theme.padForeground(pad.tint) }
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 160
            let symbolSize = min(76, max(34, geometry.size.height * 0.29))
            Button {
                if !blocked { tapFeedback += 1 }
                action()
            } label: {
                VStack(spacing: compact ? 10 : 22) {
                    Spacer(minLength: 0)
                    PadGlyph(icon: pad.icon, size: symbolSize)
                        .frame(height: symbolSize * 1.15)
                        .symbolEffect(.bounce, value: tapFeedback)
                        .symbolEffectsRemoved(reduceMotion)
                    Text(pad.title)
                        .font(.system(compact ? .body : .title3, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(foreground)
                .background(theme.padBackground(pad.tint), in: RoundedRectangle(cornerRadius: compact ? 24 : 34, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if editing {
                        Image(systemName: "pencil").font(.subheadline.weight(.semibold)).foregroundStyle(foreground.opacity(0.6)).padding(18)
                    } else if blocked {
                        Image(systemName: "lock.fill").font(.subheadline).foregroundStyle(foreground).padding(18)
                    } else if active {
                        ProgressView().tint(foreground).padding(18)
                    } else if playing {
                        Image(systemName: "stop.fill").font(.caption.weight(.bold))
                            .foregroundStyle(foreground).padding(10)
                            .background(theme == .amoled ? Palette.raised : .white.opacity(0.45), in: Circle()).padding(12)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: compact ? 24 : 34).strokeBorder(playing ? foreground.opacity(0.6) : theme == .amoled ? pad.tint.opacity(0.5) : .white.opacity(0.3), lineWidth: playing ? 3 : 1))
                .shadow(color: theme == .amoled ? .clear : pad.tint.opacity(0.12), radius: 6, y: 4)
            }.buttonStyle(PadPressStyle())
                .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: tapFeedback)
                .accessibilityLabel("\(pad.title), \(pad.typeName)")
                .accessibilityValue(blocked ? "Desktop actions disabled on PC" : playing ? "Playing" : "")
                .accessibilityHint(editing ? "Customize this button" : blocked ? "Learn about soundboard-only mode" : playing ? "Tap again to stop this sound" : "Run this action")
        }
    }
}
