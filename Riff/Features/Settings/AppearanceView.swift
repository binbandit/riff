import SwiftUI

struct AppearanceView: View {
    @Bindable private var preferences = ThemePreferences.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectionFeedback = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Set the mood.")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text("Your deck, in your colours.")
                        .foregroundStyle(.secondary)
                }
                Picker("Appearance", selection: Binding(
                    get: { preferences.theme == .amoled ? .dark : preferences.appearance },
                    set: { preferences.appearance = $0 }
                )) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.name).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(preferences.theme == .amoled)
                .accessibilityHint("Choose whether Riff follows your iPad’s appearance or always uses light or dark colours.")

                if preferences.theme == .amoled {
                    Text("AMOLED always uses dark appearance, with true black backgrounds and buttons to reduce display power use on OLED screens.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 18) {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            if preferences.theme != theme { selectionFeedback += 1 }
                            preferences.theme = theme
                        } label: {
                            ThemePreview(theme: theme, selected: preferences.theme == theme)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(theme.name)
                        .accessibilityValue(preferences.theme == theme ? "Selected" : "")
                        .accessibilityAddTraits(preferences.theme == theme ? .isSelected : [])
                        .accessibilityHint("Use this theme throughout Riff.")
                    }
                }
                Text("AMOLED keeps your button colours in icons and outlines. These settings are just for this iPad.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 600)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .background(Palette.background)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThemePreview: View {
    let theme: AppTheme
    let selected: Bool
    @Environment(\.colorScheme) private var colorScheme
    private let icons = ["sparkles", "airplane", "hand.raised", "theatermasks", "timer", "playpause"]
    private let colours = ["orange", "blue", "pink", "purple", "green", "blue"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "waveform")
                    Text("Soundboard").fontWeight(.semibold)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(theme.colors.accent)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                    ForEach(icons.indices, id: \.self) { index in
                        Image(systemName: icons[index])
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.padForeground(Palette.color(colours[index])))
                            .frame(maxWidth: .infinity)
                            .frame(height: 51)
                            .background(theme.padBackground(Palette.color(colours[index])), in: RoundedRectangle(cornerRadius: 11))
                            .overlay {
                                if theme == .amoled {
                                    RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.color(colours[index]).opacity(0.5))
                                }
                            }
                    }
                }
                HStack {
                    Image(systemName: "mic.fill")
                    Spacer()
                    Capsule().fill(theme.colors.accent).frame(width: 32, height: 5)
                    Spacer()
                    Image(systemName: "stop.fill")
                }
                .font(.caption2)
                .foregroundStyle(theme.colors.accent)
                .padding(.horizontal, 6)
            }
            .padding(14)
            .background(theme.colors.background, in: RoundedRectangle(cornerRadius: 19))
            .environment(\.colorScheme, theme.colorScheme ?? colorScheme)
            HStack {
                Text(theme.name).font(.body.weight(.semibold))
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Palette.accent : Color.secondary.opacity(0.45))
            }.padding(.horizontal, 5)
        }
        .padding(9)
        .padding(.bottom, 5)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 27))
        .overlay {
            RoundedRectangle(cornerRadius: 27)
                .strokeBorder(selected ? Palette.accent : .primary.opacity(0.08), lineWidth: selected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 27))
        .accessibilityElement(children: .ignore)
    }
}
