#if DEBUG
import SwiftUI

// Launch-only preview settings for repeatable simulator captures. No simulated PC connection.
enum DesignPreview {
    static let screen = ProcessInfo.processInfo.environment["RIFF_PREVIEW_SCREEN"] ?? ""
    static var colorScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["RIFF_PREVIEW_APPEARANCE"] {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
    static func orient() {
        guard ProcessInfo.processInfo.environment["RIFF_PREVIEW_ORIENTATION"] == "landscape",
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft)) { error in
            NSLog("Riff preview orientation: %@", error.localizedDescription)
        }
    }
}
#endif
