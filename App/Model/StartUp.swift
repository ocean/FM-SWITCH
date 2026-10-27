/// What runs first when the FM-1 switches on, before its firmware: M-VAVE's bootloader, the one
/// M-VAVE's Open V12 or V14 leaves, or m-bootloader.
///
/// The app can't read it over MIDI, so it asks, the first time a firmware's install depends on it.
enum StartUp: String, CaseIterable, Identifiable, Sendable {
    case mVave
    case mBootloader
    /// Changed by installing Open V12 or V14, which firmwares built on Felucca's earlier update code
    /// treat like m-bootloader.
    case openFirmware
    case notSure

    var id: String { rawValue }

    var name: String {
        switch self {
        case .mVave: "As it came from M-VAVE"
        case .mBootloader: "m-bootloader"
        case .openFirmware: "Changed by Open V12 or V14"
        case .notSure: "I'm not sure"
        }
    }

    /// How to tell, in a sentence, or nil for "I'm not sure".
    var detail: String? {
        switch self {
        case .mVave: "Most FM-1s. Holding REC at switch-on does nothing special."
        case .mBootloader: "Holding REC at switch-on starts its recovery mode."
        case .openFirmware: "M-VAVE's Open V12 or V14 has been installed on it."
        case .notSure: nil
        }
    }

    static let question = "Which start-up does your FM-1 have?"
    #if os(macOS)
        static let questionDetail = "We can't tell from here, and it changes what you can undo without Backup & rescue."
    #else
        static let questionDetail = "We can't tell from here, and it changes what you can undo from this iPhone."
    #endif
    static let changeLater = "You can change this later in Settings."
}

/// Firmwares built on Felucca's earlier update code, which, once the FM-1's bootloader has been
/// changed, refuse V15, Open and most other firmwares not built on Felucca.
///
/// Firmwares on the fixed code, such as LOOM-8 and Del Rio, accept V15 and aren't included.
///
/// Installing one from an iPhone is fine; getting back to M-VAVE's firmwares then usually takes a
/// Mac.
enum FeluccaUpdateCode {
    /// The firmwares known to have it, by catalogue ID.
    ///
    /// They're named in the warning, and used when a package can't be read; otherwise FM1Kit
    /// reads it from the package. Each was checked in its package's code, or for HYP-1, in its
    /// source and on an FM-1, and for Melodee, on an FM-1 (FM1Kit's findings, 2026-10-25 to
    /// 2026-10-27). ESTAMPIE has the updated check from its next release.
    static let known: [String: String] = [
        "amb": "AMB-1",
        "dub": "DUB-1",
        "felucca": "Felucca",
        "hyp1": "HYP-1",
        "melodee": "Melodee",
        "resource-hub-lof-1": "LOF-1",
    ]

    /// Whether the firmware with this catalogue ID is known to have it.
    static func isKnown(_ catalogueID: String?) -> Bool {
        catalogueID.map { known[$0] != nil } ?? false
    }

    /// The warning before installing `name`, for someone whose FM-1's bootloader has, or may have,
    /// been changed.
    struct Warning: Equatable {
        var title = Self.wayBackTitle
        var body: String
        var why = """
            Once the FM-1's bootloader has been changed, by m-bootloader or by Open V12 or V14, \
            these firmwares only accept an update that brings the same boot area the FM-1 already \
            has. V15 brings M-VAVE's, so it's refused, and so are most firmwares not built on \
            Felucca. \(Self.wayBackExplained)
            """
        var decline = "Don't install"

        init(installing catalogueID: String?, named name: String, startUp: StartUp) {
            let others = known.filter { $0.key != catalogueID }.values.sorted()
            let list = others.dropLast().joined(separator: ", ") + " and " + (others.last ?? "")
            let opening = startUp == .notSure ? "If your FM-1's bootloader has been changed, once" : "Once"
            body = """
                \(opening) \(name) is on your FM-1, you can still switch between firmwares built like \
                it (\(list)) right here.

                But to install V15, Open or most firmwares not built on Felucca, \(Self.wayBack).
                """
        }

        #if os(macOS)
            private static let wayBackTitle = "You'll need Backup & rescue to come back from this"
            private static let wayBack = "you'll need Backup & rescue"
            private static let wayBackExplained = """
                Backup & rescue writes the firmware in the chip's download mode, which works whatever \
                is installed and keeps the bootloader.
                """
        #else
            private static let wayBackTitle = "You'll need a Mac to come back from this"
            private static let wayBack = "you'll need FM-SWITCH on a Mac"
            private static let wayBackExplained = """
                On a Mac, FM-SWITCH writes the firmware in the chip's download mode, which works \
                whatever is installed and keeps the bootloader.
                """
        #endif
    }
}
