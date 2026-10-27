import AppKit
import SwiftUI

/// AppKit's look, where SwiftUI can't set it: nothing to change on the Mac.
enum SystemAppearance {
    @MainActor static func apply(for _: Look) {}
}

extension View {
    /// Light, dark, or nil to follow the Mac, for the window this view is in.
    ///
    /// SwiftUI's `preferredColorScheme(nil)` leaves a Mac window dark once it's been dark, so going
    /// from Retro, which is always dark, back to a standard look that follows the Mac stayed dark.
    /// This sets the window's own appearance instead, which nil clears.
    func windowAppearance(_ scheme: ColorScheme?) -> some View {
        background(WindowAppearance(scheme: scheme))
    }
}

/// Sets its window's appearance to `scheme`.
private struct WindowAppearance: NSViewRepresentable {
    var scheme: ColorScheme?

    func makeNSView(context _: Context) -> AppearanceSetter { AppearanceSetter() }

    func updateNSView(_ view: AppearanceSetter, context _: Context) {
        view.scheme = scheme
    }
}

/// An empty view that keeps its window's appearance to `scheme`, from when it's in one.
private final class AppearanceSetter: NSView {
    var scheme: ColorScheme? {
        didSet { apply() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    private func apply() {
        window?.appearance = scheme.flatMap { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) }
    }
}
