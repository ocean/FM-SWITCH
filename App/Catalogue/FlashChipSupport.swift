/// Which flash chips a firmware's storage and update loader accept.
///
/// FM-1 units sold from late 2026 (mostly on AliExpress) carry a UC25HQ80 (JEDEC 0xB36014)
/// instead of the Puya P25Q80 (0x856014). A firmware that only knows the Puya keeps its saves in
/// RAM on the new chip, and its update loader may refuse a later update.
enum FlashChipSupport: String, Codable, Sendable, Hashable {
    /// Knows only the first FM-1s' Puya chip.
    case old
    /// Knows both chips.
    case new
    /// Doesn't depend on the flash chip.
    case any

    /// What to tell the person, in the firmware's details.
    var summary: String {
        switch self {
        case .old: "Older chip only: saving may fail on newer FM-1s"
        case .new: "Both FM-1 flash chips"
        case .any: "Either chip"
        }
    }

    /// Whether installing it on a newer FM-1 could leave it unable to save or to update.
    var isRiskyOnNewerUnits: Bool { self == .old }
}
