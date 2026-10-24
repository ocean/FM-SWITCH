import Testing

@testable import FMSwitch

/// The standard look's colours stay readable: text at least 4.5:1 against what it sits on, and
/// icons and other shapes that carry meaning at least 3:1 (WCAG 2.2, 1.4.3 and 1.4.11), in light
/// and dark mode.
struct ContrastTests {
    typealias Shades = Palette.Shades

    static let white = Shade(0xFFFFFF)

    /// Every pairing of text and background the screens use.
    static let text: [(name: String, text: Shade, background: Shade)] = [
        ("ink on ground", Shades.ink, Shades.ground),
        ("ink on card", Shades.ink, Shades.card),
        ("ink on control", Shades.ink, Shades.control),
        ("secondary on ground", Shades.secondaryInk, Shades.ground),
        ("secondary on card", Shades.secondaryInk, Shades.card),
        ("secondary on control", Shades.secondaryInk, Shades.control),
        ("accent text on ground", Shades.accentText, Shades.ground),
        ("accent text on card", Shades.accentText, Shades.card),
        ("picked filter", Shades.card, Shades.ink),
        ("good news", Shades.goodInk, Shades.goodBackground),
        ("warning", Shades.warningInk, Shades.warningBackground),
        ("button", white, Shades.accent),
        ("firmwares button", white, Shades.firmwares),
        ("save tile", white, Shades.save),
    ]

    /// Icons and shapes that carry meaning.
    static let graphics: [(name: String, graphic: Shade, background: Shade)] = [
        ("tick on good", white, Shades.good),
        ("status dot on ground", Shades.good, Shades.ground),
        ("status dot on card", Shades.good, Shades.card),
        ("ticked box on card", Shades.firmwaresTint, Shades.card),
        ("firmwares icon on ground", Shades.firmwaresTint, Shades.ground),
        ("accent ring on card", Shades.accent, Shades.card),
    ]

    @Test(arguments: text.indices)
    func textIsReadable(_ index: Int) {
        let pair = Self.text[index]
        #expect(Self.ratio(pair.text.light, pair.background.light) >= 4.5, "\(pair.name), light")
        #expect(Self.ratio(pair.text.dark, pair.background.dark) >= 4.5, "\(pair.name), dark")
    }

    @Test(arguments: graphics.indices)
    func graphicsStandOut(_ index: Int) {
        let pair = Self.graphics[index]
        #expect(Self.ratio(pair.graphic.light, pair.background.light) >= 3, "\(pair.name), light")
        #expect(Self.ratio(pair.graphic.dark, pair.background.dark) >= 3, "\(pair.name), dark")
    }

    @Test func ratioMatchesKnownValues() {
        #expect(abs(Self.ratio(0x000000, 0xFFFFFF) - 21) < 0.01)
        #expect(abs(Self.ratio(0x767676, 0xFFFFFF) - 4.54) < 0.01)
    }

    static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
        Contrast.ratio(first, second)
    }

    /// Every badge the designer can make, its letters on both halves.
    @Test func badgeLettersAreReadable() {
        let designs = (0..<2000).map { FirmwareBadgeDesign(name: "Firmware \($0)") }
        for design in designs {
            #expect(Self.ratio(design.ink, design.first) >= 4.5, "\(design.letters) \(design.first)")
            #expect(Self.ratio(design.ink, design.second) >= 4.5, "\(design.letters) \(design.second)")
        }
        #expect(Self.ratio(FirmwareBadgeDesign(name: "M-VAVE", isOfficial: true).ink, 0x1C1C1E) >= 4.5)
    }

    /// A firmware page's title band takes whichever half the name stands out on more.
    @Test func titleBandTakesTheStrongerHalf() {
        for design in (0..<200).map({ FirmwareBadgeDesign(name: "Firmware \($0)") }) {
            let band = Self.ratio(design.ink, design.strongerHalf)
            #expect(band >= Self.ratio(design.ink, design.first))
            #expect(band >= Self.ratio(design.ink, design.second))
        }
    }
}
