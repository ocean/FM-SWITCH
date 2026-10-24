/// Which firmwares are known to work on a real FM-1.
///
/// The firmware hub asks makers to test on hardware before a firmware is listed, and
/// fm1-editor.com lists firmwares people have been using on their FM-1s, so firmwares on either
/// count as tested. Firmwares found only in aroum's FM1 Resource Hub haven't had that check, and
/// install behind a warning unless they're listed here.
enum HardwareTesting {
    /// Firmwares only in aroum's FM1 Resource Hub that have been installed on a real FM-1, and
    /// switched away from again, by catalogue ID.
    static let testedElsewhere: Set<String> = []
}

extension CatalogueEntry {
    /// Whether the firmware is known to install, and to let another be installed after it, on a
    /// real FM-1.
    var isHardwareTested: Bool {
        isOfficial || !listing.isDisjoint(with: [.hub, .editor]) || HardwareTesting.testedElsewhere.contains(id)
    }
}
