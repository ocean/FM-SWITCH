import Foundation

/// The releases of a firmware saved here: each release and build saved is kept, so a stable
/// release and a test one can both be to hand.
extension FirmwareLibrary {
    /// Every saved copy of this catalogue firmware.
    func savedCopies(of entry: CatalogueEntry) -> [StoredFirmware] {
        items.filter { $0.catalogueID == entry.id }
    }

    /// Whether the stable release, or the test one, is saved, for a firmware that has both.
    func isSaved(test: Bool, of entry: CatalogueEntry) -> Bool {
        stored(for: entry.beta == test ? entry : entry.choosingOtherRelease()) != nil
    }
}
