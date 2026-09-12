import SwiftUI

@main struct RiffApp: App {
    @State private var store = RiffStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(store).tint(Palette.accent)
#if DEBUG
                .preferredColorScheme(ThemePreferences.shared.theme.colorScheme ?? DesignPreview.colorScheme ?? ThemePreferences.shared.colorScheme)
#else
                .preferredColorScheme(ThemePreferences.shared.colorScheme)
#endif
        }
    }
}
