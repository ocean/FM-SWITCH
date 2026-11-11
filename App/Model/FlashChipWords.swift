import Foundation

/// What to tell the person about the FM-1's two flash chips, for both looks.
///
/// FM-1s sold since autumn 2026 have a newer flash chip, which firmwares that only know the first
/// one can't save on. Only some firmwares say which chip the FM-1 has, so when it hasn't said,
/// the person is told how to tell.
enum FlashChipWords {
    /// What the firmwares named do on an FM-1 with the newer chip, given whether the FM-1 says it
    /// has that chip and whether FM-SWITCH refuses them, as The Firmware Hub lists them as
    /// knowing only the older one.
    static func warning(_ names: [String], hasNewerFlashChip: Bool, refuses: Bool = false) -> String {
        let name = ListFormatter.localizedString(byJoining: names)
        let one = names.count == 1
        if refuses {
            return """
                The Firmware Hub lists \(name) as only knowing the older flash chip, and your FM-1 has the \
                newer one, so FM-SWITCH won't install \(one ? "it" : "them"). On that chip, \(name) usually \
                \(one ? "keeps" : "keep") changes only until it's switched off, and often can't install \
                another firmware.
                """
        }
        if hasNewerFlashChip {
            return """
                Your FM-1 has the newer flash chip, and \(name) \(one ? "looks" : "look") like \
                \(one ? "it only knows" : "they only know") the older one. If so, on your FM-1 \
                \(one ? "it usually keeps" : "they usually keep") changes only until it's switched off, and \
                often can't install another firmware.
                """
        }
        return """
            \(name) only \(one ? "knows" : "know") the older FM-1 flash chip. On an FM-1 with the newer chip, \
            \(one ? "it usually keeps" : "they usually keep") changes only until it's switched off, and \
            \(one ? "it often can't" : "they often can't") install another firmware.
            """
    }

    /// The choice to install a firmware that looks like it only knows the older chip.
    static let installAnyway = "Install it anyway"

    /// Why installing it anyway can be right.
    static let installAnywayDetail = "FM-SWITCH can't always tell which chips a firmware knows, so it may work."

    /// The heading of the guide to telling which chip an FM-1 has.
    static let howToTellQuestion = "How would I know?"

    /// How to tell which chip an FM-1 has by looking at it.
    static let howToTell = """
        FM-1s sold since autumn 2026 have the newer chip. The easiest way to tell so far is the M-VAVE \
        logo: on newer FM-1s it's on the front, under the screen. On older ones it's on the top, near \
        the USB and MIDI sockets.
        """
}
