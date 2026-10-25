/// What runs first when the FM-1 switches on, before its firmware: M-VAVE's bootloader, or
/// m-bootloader.
///
/// The app can't read it over MIDI, so it asks, the first time a firmware's install depends on it.
enum StartUp: String, CaseIterable, Identifiable, Sendable {
    case mVave
    case mBootloader
    case notSure

    var id: String { rawValue }

    var name: String {
        switch self {
        case .mVave: "As it came from M-VAVE"
        case .mBootloader: "m-bootloader"
        case .notSure: "I'm not sure"
        }
    }

    /// How to tell, in a sentence, or nil for "I'm not sure".
    var detail: String? {
        switch self {
        case .mVave: "Most FM-1s. Holding REC at switch-on does nothing special."
        case .mBootloader: "Holding REC at switch-on starts its recovery mode."
        case .notSure: nil
        }
    }

    static let question = "Which start-up does your FM-1 have?"
    static let questionDetail = "We can't tell from here, and it changes what you can undo from this iPhone."
    static let changeLater = "You can change this later in Settings."
}

/// Firmwares built on Felucca's update code, which, while m-bootloader is on the FM-1, refuse the
/// packages that would take it back to V15 or Open V12.
///
/// Installing one from an iPhone is fine; getting back to M-VAVE's firmwares then takes a Mac.
enum FeluccaUpdateCode {
    /// The firmwares known to have it, by catalogue ID.
    ///
    /// They're named in the warning, and used when a package can't be read; otherwise FM1Kit
    /// reads it from the package. Each was checked in its package's code, or for HYP-1, in its
    /// source and on an FM-1 (FM1Kit's findings, 2026-10-25).
    static let known: [String: String] = [
        "amb": "AMB-1",
        "dub": "DUB-1",
        "felucca": "Felucca",
        "fm1-editor-estampie": "Estampie",
        "hyp1": "HYP-1",
        "resource-hub-lof-1": "LOF-1",
    ]

    /// Whether the firmware with this catalogue ID is known to have it.
    static func isKnown(_ catalogueID: String?) -> Bool {
        catalogueID.map { known[$0] != nil } ?? false
    }

    /// The warning before installing `name`, for someone whose FM-1 has, or may have, m-bootloader.
    struct Warning: Equatable {
        var title = "You'll need a Mac to come back from this"
        var body: String
        var why = """
            With m-bootloader on the FM-1, these firmwares only accept an update that brings the \
            same boot area the FM-1 already has. V15 and Open V12 bring M-VAVE's, so they're \
            refused. On a Mac, FM-SWITCH writes the flash directly in the chip's download mode, \
            which works whatever is installed and keeps m-bootloader.
            """
        var keep = "Keep things as they are"

        init(installing catalogueID: String?, named name: String, startUp: StartUp) {
            let others = known.filter { $0.key != catalogueID }.values.sorted()
            let list = others.dropLast().joined(separator: ", ") + " and " + (others.last ?? "")
            let opening = startUp == .notSure ? "If your FM-1 has m-bootloader, once" : "Once"
            body = """
                \(opening) \(name) is on your FM-1, you can still switch between firmwares built like \
                it (\(list)) right here.

                But to go back to V15 or Open V12, you'll need FM-SWITCH on a Mac.
                """
        }
    }
}
