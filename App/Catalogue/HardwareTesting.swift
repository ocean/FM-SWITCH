/// Which firmwares are known to work on a real FM-1.
///
/// The Firmware Hub asks makers to test on hardware before a firmware is listed, and
/// fm1-editor.com lists firmwares people have been using on their FM-1s, so firmwares on either
/// count as tested. Firmwares found only in aroum's FM1 Resource Hub or on mutant.cloud (which
/// anyone can add to) haven't had that check, and install behind a warning unless they're listed
/// here.
enum HardwareTesting {
    /// Firmwares only in aroum's FM1 Resource Hub or on mutant.cloud that have been installed on a real FM-1, and
    /// switched away from again, by catalogue ID.
    static let testedElsewhere: Set<String> = []
}

extension CatalogueEntry {
    /// Whether the firmware is known to install, and to let another be installed after it, on a
    /// real FM-1.
    var isHardwareTested: Bool {
        isOfficial || !listing.isDisjoint(with: [.hub, .editor]) || HardwareTesting.testedElsewhere.contains(id)
    }

    /// Whether only its maker lists the firmware, on mutant.cloud, with no one else having checked it.
    ///
    /// The list hides these unless the settings ask for them, or a copy is saved here.
    var isListedOnlyByItsMaker: Bool {
        listing == .mutantCloud && !isHardwareTested
    }

    /// Why the firmware is in testing, for its page.
    var inTestingNote: String {
        if isListedOnlyByItsMaker {
            return """
                In testing: listed only by its maker, on mutant.cloud, so no one else has checked it, \
                and it may not have been widely tested on a real FM-1.
                """
        }
        return """
            In testing: not yet known to work on a real FM-1. It's only listed in aroum's FM1 Resource \
            Hub or on mutant.cloud, not on The Firmware Hub or fm1-editor.com.
            """
    }
}
