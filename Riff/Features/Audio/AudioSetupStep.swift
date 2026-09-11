import SwiftUI

struct AudioSetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number.formatted())
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Palette.accent)
                .frame(width: 28, height: 28)
                .background(Palette.accent.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
