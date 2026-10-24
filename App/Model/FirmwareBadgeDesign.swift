import func Foundation.cos
import func Foundation.pow
import func Foundation.sin

/// A firmware's badge: two characters on two colours of its own, so each firmware in the list is
/// recognisable at a glance.
///
/// Everything comes from the firmware's name, so a badge never changes while the name stays the
/// same, whatever else joins the list. The badge is split in two, across or corner to corner, into
/// a light half and a dark one: 16 hues, at least five apart, in two tones, either way up and in
/// either shape make 896 designs, so neighbours in the list rarely look alike.
struct FirmwareBadgeDesign: Equatable {
    /// Bright halves with white letters, or pastel halves with dark letters.
    enum Tone: CaseIterable {
        case pale
        case deep
    }

    /// Where the two colours meet.
    enum Split: CaseIterable {
        /// Top and bottom.
        case across
        /// The top-left corner's half, and the bottom-right corner's.
        case diagonal
    }

    var letters: String
    /// The top or top-left half, as `0xRRGGBB`.
    var first: UInt32
    /// The other half, as `0xRRGGBB`.
    var second: UInt32
    var split: Split
    /// The letters' colour, as `0xRRGGBB`, at least 4.5:1 on both halves.
    var ink: UInt32

    /// The half the letters stand out on more, for one-colour backgrounds like a firmware page's
    /// title band.
    var strongerHalf: UInt32 {
        Contrast.ratio(first, ink) >= Contrast.ratio(second, ink) ? first : second
    }

    /// The badge from the name alone.
    ///
    /// M-VAVE's official firmware is black and white with its version, such as "V15", which no other
    /// badge can have, as theirs are two characters.
    init(name: String, isOfficial: Bool = false, version: String? = nil) {
        guard !isOfficial else {
            let letters = version.flatMap { $0.count <= 4 ? $0 : nil } ?? Self.letters(of: name)
            self.init(letters: letters, first: 0x1C1C1E, second: 0x1C1C1E, split: .across, ink: 0xFFFFFF)
            return
        }
        let seed = Self.seed(of: name)
        let lightHue = Int(seed % UInt32(Self.hueCount))
        let darkHue = (lightHue + 5 + Int((seed >> 8) % 7)) % Self.hueCount
        let tone: Tone = (seed >> 16) & 1 == 0 ? .pale : .deep
        let colours = Self.colours(lightHue: lightHue, darkHue: darkHue, tone: tone)
        let isLightFirst = (seed >> 20) & 1 == 0
        self.init(
            letters: Self.letters(of: name),
            first: isLightFirst ? colours.light : colours.dark,
            second: isLightFirst ? colours.dark : colours.light,
            split: (seed >> 24) & 1 == 0 ? .across : .diagonal,
            ink: colours.ink)
    }

    private init(letters: String, first: UInt32, second: UInt32, split: Split, ink: UInt32) {
        self.letters = letters
        self.first = first
        self.second = second
        self.split = split
        self.ink = ink
    }

    // MARK: - Letters.

    /// Words that don't tell firmwares apart, so they aren't used for letters.
    private static let commonWords: Set<String> = [
        "firmware", "official", "the", "for", "of", "and", "fm", "fm1", "fm-1",
    ]

    /// Two characters from the name.
    ///
    /// They're the first and last words' initials, or for one word, the initials of its parts
    /// ("AMB-1" gives "A1", "AmbWave" "AW"), or its first two characters as written ("Felucca"
    /// gives "Fe", "SLOOP" "SL"). Words like "firmware" and "FM1" are skipped.
    static func letters(of name: String) -> String {
        let allWords = name.split { !$0.isLetter && !$0.isNumber && $0 != "-" }
            .map(String.init)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
        let distinctive = allWords.filter { !commonWords.contains($0.lowercased()) }
        let words = distinctive.isEmpty ? allWords : distinctive
        guard let first = words.first, let last = words.last else { return "?" }
        if words.count > 1 { return (initial(of: first) + initial(of: last)).uppercased() }
        let allParts = self.parts(of: first)
        let distinctiveParts = allParts.filter { !commonWords.contains($0.lowercased()) }
        let parts = distinctiveParts.isEmpty ? allParts : distinctiveParts
        if parts.count > 1, let lastPart = parts.last {
            return (initial(of: parts[0]) + initial(of: lastPart)).uppercased()
        }
        let characters = (parts.first ?? first).filter { $0.isLetter || $0.isNumber }
        return characters.prefix(1).uppercased() + characters.dropFirst().prefix(1)
    }

    private static func initial(of word: String) -> String {
        word.first { $0.isLetter || $0.isNumber }.map(String.init) ?? ""
    }

    /// A word split at hyphens and where a lower-case letter meets a capital.
    private static func parts(of word: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var previous: Character?
        for character in word {
            if character == "-" {
                parts.append(current)
                current = ""
            } else {
                if let previous, previous.isLowercase, character.isUppercase {
                    parts.append(current)
                    current = ""
                }
                current.append(character)
            }
            previous = character
        }
        parts.append(current)
        return parts.filter { $0.contains { $0.isLetter || $0.isNumber } }
    }

    // MARK: - Colours.

    /// How many hues the halves are picked from, evenly spaced as the eye sees them.
    static let hueCount = 16

    /// The name, ignoring case and punctuation, hashed with FNV-1a, which (unlike `hashValue`) is
    /// the same on every launch.
    static func seed(of name: String) -> UInt32 {
        let normalised = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalised.utf8.reduce(UInt32(2_166_136_261)) { hash, byte in (hash ^ UInt32(byte)) &* 16_777_619 }
    }

    /// The two halves and the letters, with the light half darkened, or the letters moved away
    /// from both halves, until the letters are readable on each.
    private static func colours(lightHue: Int, darkHue: Int, tone: Tone) -> (light: UInt32, dark: UInt32, ink: UInt32) {
        let (light, dark) = (hue(lightHue), hue(darkHue))
        switch tone {
        case .pale:
            let lightHalf = oklch(lightness: 0.95, chroma: 0.05, hue: light)
            let darkHalf = oklch(lightness: 0.80, chroma: 0.13, hue: dark)
            var lightness = 0.27
            var ink: UInt32 { oklch(lightness: lightness, chroma: 0.07, hue: light) }
            while min(Contrast.ratio(ink, lightHalf), Contrast.ratio(ink, darkHalf)) < 4.5 {
                lightness -= 0.01
            }
            return (lightHalf, darkHalf, ink)
        case .deep:
            let white: UInt32 = 0xFFFFFF
            var lightness = 0.60
            while Contrast.ratio(white, oklch(lightness: lightness, chroma: 0.15, hue: light)) < 4.5 {
                lightness -= 0.01
            }
            return (
                oklch(lightness: lightness, chroma: 0.15, hue: light),
                oklch(lightness: 0.33, chroma: 0.12, hue: dark),
                white
            )
        }
    }

    /// The hue of one of the 16 steps, in degrees.
    private static func hue(_ step: Int) -> Double {
        25 + Double(step) * 360 / Double(hueCount)
    }

    /// OKLCH to `0xRRGGBB`, clipped to sRGB.
    ///
    /// OKLCH is used because equal steps of its hue look equally different, unlike HSL's, where
    /// greens take up a quarter of the wheel.
    private static func oklch(lightness: Double, chroma: Double, hue degrees: Double) -> UInt32 {
        let angle = degrees * .pi / 180
        // OKLab's a (green to red) and b (blue to yellow).
        let (greenRed, blueYellow) = (chroma * cos(angle), chroma * sin(angle))
        let long = pow(lightness + 0.396_337_777_4 * greenRed + 0.215_803_757_3 * blueYellow, 3)
        let medium = pow(lightness - 0.105_561_345_8 * greenRed - 0.063_854_172_8 * blueYellow, 3)
        let short = pow(lightness - 0.089_484_177_5 * greenRed - 1.291_485_548_0 * blueYellow, 3)
        let linear = [
            4.076_741_662_1 * long - 3.307_711_591_3 * medium + 0.230_969_929_2 * short,
            -1.268_438_004_6 * long + 2.609_757_401_1 * medium - 0.341_319_396_5 * short,
            -0.004_196_086_3 * long - 0.703_418_614_7 * medium + 1.707_695_658_0 * short,
        ]
        return linear.reduce(UInt32(0)) { value, channel in
            let clipped = min(max(channel, 0), 1)
            let encoded = clipped <= 0.003_130_8 ? 12.92 * clipped : 1.055 * pow(clipped, 1 / 2.4) - 0.055
            return value << 8 | UInt32((encoded * 255).rounded())
        }
    }
}

/// WCAG's contrast ratio between two sRGB colours.
enum Contrast {
    static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
        let (one, two) = (luminance(first), luminance(second))
        return (max(one, two) + 0.05) / (min(one, two) + 0.05)
    }

    static func luminance(_ rgb: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift in
            let value = Double((rgb >> UInt32(shift)) & 0xFF) / 255
            return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}

extension CatalogueEntry {
    /// The firmware's badge.
    var badge: FirmwareBadgeDesign {
        FirmwareBadgeDesign(name: name, isOfficial: isOfficial, version: version)
    }
}
