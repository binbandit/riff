import SwiftUI

struct PadGlyph: View {
    let icon: String
    var size: CGFloat = 64
    var body: some View {
        if icon.hasPrefix("emoji:") {
            Text(String(icon.dropFirst(6))).font(.system(size: size))
        } else {
            Image(systemName: icon).font(.system(size: size, weight: .medium, design: .rounded))
                .symbolRenderingMode(.hierarchical)
        }
    }
}
