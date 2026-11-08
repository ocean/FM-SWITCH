/// What runs first when the FM-1 switches on, before its firmware: M-VAVE's bootloader as V15 or
/// V16 brings it, the one M-VAVE's Open V12 or V14 leaves, or m-bootloader.
///
/// The app can't read it over MIDI, so it asks, the first time a firmware's install depends on it.
enum StartUp: String, CaseIterable, Identifiable, Sendable {
    case mVave
    /// Changed by installing V16, which brings a bootloader of its own.
    case v16
    case mBootloader
    /// Changed by installing Open V12 or V14, which firmwares built on Felucca's earlier update code
    /// treat like m-bootloader.
    case openFirmware
    case notSure

    var id: String { rawValue }

    var name: String {
        switch self {
        case .mVave: "As it came from M-VAVE"
        case .v16: "Changed by V16"
        case .mBootloader: "m-bootloader"
        case .openFirmware: "Changed by Open V12 or V14"
        case .notSure: "I'm not sure"
        }
    }

    /// How to tell, in a sentence, or nil for "I'm not sure".
    var detail: String? {
        switch self {
        case .mVave: "Most FM-1s. Holding REC at switch-on does nothing special."
        case .v16: "M-VAVE's V16 has been installed on it."
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
