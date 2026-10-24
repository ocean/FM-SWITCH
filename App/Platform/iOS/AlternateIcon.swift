import UIKit

/// The Home Screen icon: the standard one, or Retro's pixel-art one.
@MainActor
enum AlternateIcon {
    private static let retroName = "RetroIcon"

    static var isAvailable: Bool { UIApplication.shared.supportsAlternateIcons }

    static var isRetro: Bool { UIApplication.shared.alternateIconName == retroName }

    /// Changes the icon. iOS tells the person it's changed.
    static func set(retro: Bool) async throws {
        try await UIApplication.shared.setAlternateIconName(retro ? retroName : nil)
    }
}
