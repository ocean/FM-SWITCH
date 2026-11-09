import Foundation

/// What to tell the person about the FM-1's two flash chips, for both looks.
///
/// FM-1s sold since autumn 2026 have a newer flash chip, which firmwares that only know the first
/// one can't save on. Only some firmwares say which chip the FM-1 has, so when it hasn't said,
/// the person is told how to tell.
enum FlashChipWords {
    /// What the firmwares named do on an FM-1 with the newer chip, given whether the FM-1 says it
    /// has that chip.
    static func warning(_ names: [String], hasNewerFlashChip: Bool) -> String {
        let name = ListFormatter.localizedString(byJoining: names)
        if hasNewerFlashChip {
            return """
                Your FM-1 has the newer flash chip, which \(name) doesn't know. On it, \(name) usually keeps \
                changes only until it's switched off, and it often can't install another firmware.
                """
        }
        let one = names.count == 1
        return """
            \(name) only \(one ? "knows" : "know") the older FM-1 flash chip. On an FM-1 with the newer chip, \
            \(one ? "it usually keeps" : "they usually keep") changes only until it's switched off, and \
            \(one ? "it often can't" : "they often can't") install another firmware.
            """
    }

    /// The heading of the guide to telling which chip an FM-1 has.
    static let howToTellQuestion = "How would I know?"

    /// How to tell which chip an FM-1 has by looking at it.
    static let howToTell = """
        FM-1s sold since autumn 2026 have the newer chip. The easiest way to tell so far is the M-VAVE \
        logo: on newer FM-1s it's on the front, under the screen. On older ones it's on the top, near \
        the USB and MIDI sockets.
        """
}
