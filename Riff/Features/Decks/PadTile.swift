import SwiftUI
import UIKit

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
    var queuePosition: Int?
    var blocked = false
    var switched = false
    var gestureAction: (PadGesture) -> Void = { _ in }
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
                .overlay(alignment: .bottomLeading) {
                    if pad.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(foreground.opacity(0.65)).padding(14).accessibilityLabel("Pinned to every page") }
                }
                .overlay(alignment: .topLeading) {
                    if pad.isLooping {
                        Image(systemName: "repeat").font(.caption.weight(.semibold))
                            .foregroundStyle(foreground.opacity(0.7)).padding(14)
                    } else if pad.kind == "switch", !editing {
                        Text(switched ? "2" : "1").font(.caption.weight(.bold))
                            .foregroundStyle(foreground).padding(10)
                            .background(foreground.opacity(0.12), in: Circle()).padding(12)
                            .accessibilityLabel(switched ? "Second sequence next" : "First sequence next")
                    }
                }
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
                    } else if let queuePosition {
                        Text("\(queuePosition)").font(.caption.weight(.bold)).monospacedDigit()
                            .foregroundStyle(foreground).padding(10)
                            .background(theme == .amoled ? Palette.raised : .white.opacity(0.45), in: Circle()).padding(12)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: compact ? 24 : 34).strokeBorder(playing ? foreground.opacity(0.6) : theme == .amoled ? pad.tint.opacity(0.5) : .white.opacity(0.3), lineWidth: playing ? 3 : 1))
                .shadow(color: theme == .amoled ? .clear : pad.tint.opacity(0.12), radius: 6, y: 4)
            }.buttonStyle(PadPressStyle())
                .allowsHitTesting(!pad.hasKeyLogic || editing)
                .overlay {
                    if pad.hasKeyLogic && !editing {
                        PadGestureSurface(doubleTap: pad.doubleTapAction != nil, hold: pad.holdAction != nil) { gesture in
                            tapFeedback += 1
                            if gesture == .tap { action() } else { gestureAction(gesture) }
                        }
                        .id(pad)
                        .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if pad.hasKeyLogic && !editing {
                        HStack(spacing: 5) {
                            if pad.doubleTapAction != nil { Text("2×") }
                            if pad.holdAction != nil { Image(systemName: "hand.tap") }
                        }.font(.caption.weight(.semibold)).foregroundStyle(foreground.opacity(0.7)).padding(14)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityAction { action() }
                .accessibilityActions {
                    if !editing, pad.doubleTapAction != nil { Button("Double-tap action") { gestureAction(.doubleTap) } }
                    if !editing, pad.holdAction != nil { Button("Hold action") { gestureAction(.hold) } }
                }
                .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: tapFeedback)
                .accessibilityLabel("\(pad.title), \(pad.typeName)")
                .accessibilityValue(blocked ? "Desktop actions disabled on PC" : playing ? (pad.isLooping ? "Looping" : "Playing") : queuePosition != nil ? "Queued, position \(queuePosition ?? 0)" : pad.kind == "switch" ? (switched ? "Second sequence next" : "First sequence next") : "")
                .accessibilityHint(editing ? "Customize this button" : blocked ? "Learn about soundboard-only mode" : playing ? "Tap again to stop this sound" : queuePosition != nil ? "Tap again to remove from queue" : "Run this action")
        }
    }
}

// UIKit's failure dependencies ensure only one action fires, and movement cancels
// taps/holds before the surrounding page scroller takes over.
private struct PadGestureSurface: UIViewRepresentable {
    var doubleTap: Bool
    var hold: Bool
    var perform: (PadGesture) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(perform: perform) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isAccessibilityElement = false
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        view.addGestureRecognizer(single)
        if doubleTap {
            let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap))
            double.numberOfTapsRequired = 2
            single.require(toFail: double)
            view.addGestureRecognizer(double)
        }
        if hold {
            let long = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold))
            long.minimumPressDuration = 0.55
            long.allowableMovement = 12
            for recognizer in view.gestureRecognizers ?? [] { recognizer.require(toFail: long) }
            view.addGestureRecognizer(long)
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.perform = perform
        uiView.isUserInteractionEnabled = context.environment.isEnabled
    }
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.perform = { _ in }
        for recognizer in uiView.gestureRecognizers ?? [] { recognizer.isEnabled = false }
    }
    final class Coordinator: NSObject {
        var perform: (PadGesture) -> Void
        init(perform: @escaping (PadGesture) -> Void) { self.perform = perform }
        @objc func tap(_ recognizer: UITapGestureRecognizer) { if recognizer.state == .ended { perform(.tap) } }
        @objc func doubleTap(_ recognizer: UITapGestureRecognizer) { if recognizer.state == .ended { perform(.doubleTap) } }
        @objc func hold(_ recognizer: UILongPressGestureRecognizer) { if recognizer.state == .began { perform(.hold) } }
    }
}
