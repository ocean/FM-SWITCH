import AppKit
import SwiftUI

/// FM-SWITCH ▸ Settings… (⌘,): brings the window forward, or opens it if it was closed, and shows
/// Settings in it, in whichever look is on.
struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow
    var model: AppModel

    var body: some View {
        Button("Settings…") {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: FMSwitchApp.mainWindow)
            }
            model.requestedPage = .settings
        }
        .keyboardShortcut(",")
    }
}
