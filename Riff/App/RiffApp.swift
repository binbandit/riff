import SwiftUI

@main struct RiffApp: App {
    @State private var store = RiffStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(store).tint(Palette.accent)
#if DEBUG
                .preferredColorScheme(DesignPreview.colorScheme ?? ThemePreferences.shared.appearance.colorScheme)
#else
                .preferredColorScheme(ThemePreferences.shared.appearance.colorScheme)
#endif
        }
    }
}
