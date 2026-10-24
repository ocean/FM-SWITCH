import UIKit

/// UIKit's look, where SwiftUI can't set it.
enum SystemAppearance {
    /// Hides the system spinner in Retro, whose pull to refresh draws a PixelSpinner instead.
    ///
    /// The standard look keeps the system spinner. It applies to lists made after it's called,
    /// which a change of look is.
    @MainActor static func apply(for look: Look) {
        UIRefreshControl.appearance().tintColor = look == .retro ? .clear : nil
    }
}
