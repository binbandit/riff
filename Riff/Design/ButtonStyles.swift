import SwiftUI

struct PadPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.medium)).foregroundStyle(.primary)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Palette.raised.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }
}
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).foregroundStyle(Palette.accentInk)
            .padding(.horizontal, 22).padding(.vertical, 15)
            .background(Palette.accent, in: Capsule()).opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
    }
}
