import AppKit

/// What to call the device the app is running on, in the app's text.
enum ThisDevice {
    @MainActor
    static var name: String { "Mac" }
}

/// The system clipboard: a link's Copy Link, and an install problem's details.
enum Pasteboard {
    @MainActor
    static func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .URL)
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @MainActor
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
