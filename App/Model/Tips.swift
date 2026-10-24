import Foundation

/// Tips for the app's maker.
///
/// iPhone and iPad take them as in-app purchases, which the App Store requires there. The Mac
/// app comes from fm-1.drewr.dev rather than the Mac App Store, which in-app purchases need, so it
/// links to Ko-fi instead.
enum Tips {
    static let koFi = URL(literal: "https://ko-fi.com/oceanicity")

    /// The App Store's tips, smallest first: a nibble ($2), a byte ($5) and a kilobyte ($10).
    static let productIDs = [
        "dev.drewr.fmswitch.tip.nibble",
        "dev.drewr.fmswitch.tip.byte",
        "dev.drewr.fmswitch.tip.kilobyte",
    ]

    static let note = "FM-SWITCH is free. If it's helped you, a tip helps keep it going. Tips don't unlock anything."

    static let thanks = "Thank you for the tip. It means a lot."

    static let unavailable = "The App Store isn't taking tips right now. Try again later."
}

/// A card that slides up from the bottom after the fifth install, and again after the fifteenth.
///
/// Each shows once. Someone who reaches the fifteenth without having seen the first sees only the
/// second.
enum TipNudge: Int, CaseIterable {
    case fifthInstall = 5
    case fifteenthInstall = 15

    var title: String {
        switch self {
        case .fifthInstall: "Wow, looks like you're enjoying switching firmwares!"
        case .fifteenthInstall: "Fifteen firmwares and counting!"
        }
    }

    var message: String {
        switch self {
        case .fifthInstall:
            """
            That's five installs. FM-SWITCH is free, but if you like it and would like to support more \
            open source development, a tip helps keep it going.
            """
        case .fifteenthInstall:
            """
            You're getting the most out of your FM-1. If FM-SWITCH has helped and you'd like to support \
            more open source development, a tip helps keep it going.
            """
        }
    }

    /// The cards reached after this many installs.
    static func reached(installs: Int) -> [Self] {
        allCases.filter { $0.rawValue <= installs }
    }

    /// The card to show, if one's been reached since the last was shown.
    static func due(installs: Int, shown: Int) -> Self? {
        let reached = reached(installs: installs)
        return reached.count > shown ? reached.last : nil
    }
}

/// One tip the App Store offers, with its price in the person's own currency.
struct Tip: Identifiable, Equatable {
    let id: String
    let name: String
    let price: String
}
