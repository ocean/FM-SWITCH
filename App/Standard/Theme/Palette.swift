import SwiftUI

/// A colour's light-mode and dark-mode values, kept as numbers so tests can check their contrast.
struct Shade: Equatable {
    var light: UInt32
    var dark: UInt32

    init(light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    /// The same in both modes.
    init(_ both: UInt32) {
        self.init(light: both, dark: both)
    }
}

/// The standard look's colours: a warm stone ground with white cards.
///
/// Each has a dark-mode partner. `ContrastTests` checks that text passes 4.5:1 on what it sits on,
/// and icons 3:1, in both modes.
enum Palette {
    /// The values, for the colours below and for the tests.
    enum Shades {
        static let ground = Shade(light: 0xEEE8DD, dark: 0x141413)
        static let card = Shade(light: 0xFFFFFF, dark: 0x232321)
        static let control = Shade(light: 0xE2DBCD, dark: 0x2C2B29)
        static let line = Shade(light: 0xE8E2D7, dark: 0x33322F)
        static let ink = Shade(light: 0x1C1C1E, dark: 0xF2F1EE)
        static let secondaryInk = Shade(light: 0x5E5E63, dark: 0xA8A6A1)
        static let accent = Shade(0xC2410C)
        static let accentText = Shade(light: 0x5B21B6, dark: 0xFF9259)
        static let firmwares = Shade(0x6D28D9)
        static let firmwaresTint = Shade(light: 0x6D28D9, dark: 0xA78BFA)
        static let save = Shade(0x2563EB)
        static let good = Shade(light: 0x1F8A45, dark: 0x2E9E57)
        static let goodInk = Shade(light: 0x17602F, dark: 0x86D9A2)
        static let goodBackground = Shade(light: 0xE3F1E7, dark: 0x173322)
        static let warningInk = Shade(light: 0x7A3E00, dark: 0xFFC58A)
        static let warningBackground = Shade(light: 0xFFF4E5, dark: 0x3A2610)
    }

    /// Behind everything.
    static let ground = Color(Shades.ground)
    /// Cards, rows and grouped sections.
    static let card = Color(Shades.card)
    /// Controls that sit on the ground, such as the search field and unpicked filters.
    static let control = Color(Shades.control)
    /// Hairlines between rows.
    static let line = Color(Shades.line)
    /// Body text.
    static let ink = Color(Shades.ink)
    /// Secondary text.
    static let secondaryInk = Color(Shades.secondaryInk)

    /// The app's accent: buttons and controls.
    static let accent = Color(Shades.accent)
    /// Links and text buttons: a deep violet in light mode, where orange text looked weak, and a
    /// lighter orange in dark mode.
    static let accentText = Color(Shades.accentText)

    /// Firmwares: the firmware list, everywhere it's offered.
    static let firmwares = Color(Shades.firmwares)
    /// Firmwares' purple for icons and outlines, lighter in dark mode so it stands out.
    static let firmwaresTint = Color(Shades.firmwaresTint)
    /// Saving the FM-1.
    static let save = Color(Shades.save)

    /// Good news: connected, done.
    static let good = Color(Shades.good)
    /// Text on ``goodBackground``.
    static let goodInk = Color(Shades.goodInk)
    static let goodBackground = Color(Shades.goodBackground)
    /// A warning's text, and its background.
    static let warningInk = Color(Shades.warningInk)
    static let warningBackground = Color(Shades.warningBackground)
}

extension Color {
    /// A colour with a value for light mode and one for dark mode.
    init(_ shade: Shade) {
        #if os(iOS)
            self.init(
                uiColor: UIColor { traits in
                    UIColor(Color(rgb: traits.userInterfaceStyle == .dark ? shade.dark : shade.light))
                })
        #else
            self.init(
                nsColor: NSColor(name: nil) { appearance in
                    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    return NSColor(Color(rgb: isDark ? shade.dark : shade.light))
                })
        #endif
    }
}
