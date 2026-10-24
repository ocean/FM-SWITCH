import SafariServices
import SwiftUI
import UIKit

/// Opens web links in Safari's own view over the app, with Safari's privacy protections, content
/// blockers, saved passwords and downloads, and a button to carry on in Safari itself.
enum InAppBrowser {
    /// Shows `url` in Safari's view, from whatever is on top, sheets included.
    ///
    /// Anything that isn't a web page, such as a mail link, goes to the system as usual.
    @MainActor
    static func open(_ url: URL) -> OpenURLAction.Result {
        guard ["http", "https"].contains(url.scheme?.lowercased()), let presenter = topmost() else {
            return .systemAction
        }
        let safari = SFSafariViewController(url: url)
        safari.modalPresentationStyle = .pageSheet
        presenter.present(safari, animated: true)
        return .handled
    }

    /// The screen on top in the window the person is using.
    @MainActor
    private static func topmost() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.filter { $0.activationState == .foregroundActive }
        let window = active.flatMap(\.windows).first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

extension View {
    /// Opens the web links inside this view in Safari's view over the app.
    func opensLinksInApp() -> some View {
        environment(\.openURL, OpenURLAction { InAppBrowser.open($0) })
    }
}
