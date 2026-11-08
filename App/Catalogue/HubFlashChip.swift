import FM1Kit

/// The Firmware Hub's `chip` field, which says which of the FM-1's flash chips a firmware knows
/// before its package is downloaded.
///
/// FM-1s sold from autumn 2026 carry a UC25HQ80 (JEDEC 0xB36014) instead of the Puya P25Q80
/// (0x856014). Each value matches what FM1Kit reads from a package's code.
enum HubFlashChip: String, Codable, Sendable, Hashable {
    /// Knows only the first FM-1s' chip.
    case old
    /// Knows both chips.
    case new
    /// Doesn't check the chip.
    case any

    /// The same support, as FM1Kit reads it from a package.
    var support: FlashChipSupport {
        switch self {
        case .old: .firstChipOnly
        case .new: .bothChips
        case .any: .noCheck
        }
    }

    /// Which FM-1s it keeps its saves on, for a firmware's details.
    var savesOn: String {
        switch self {
        case .old: "Older FM-1s only"
        case .new: "All FM-1s"
        case .any: "All FM-1s (doesn't check the chip)"
        }
    }
}
