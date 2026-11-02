import Testing

@testable import FMSwitch

/// The firmware list's orders: by name, the newest release first, or the most installed first.
struct FirmwareOrderTests {
    private let byName = [
        CatalogueEntry(id: "a", name: "A", date: "2026-03-01", listing: .hub),
        CatalogueEntry(id: "b", name: "B", listing: .hub),
        CatalogueEntry(id: "c", name: "C", date: "2026-10-16", listing: .hub),
        CatalogueEntry(id: "d", name: "D", date: "2026-03-01", listing: .hub),
    ]

    @Test func keepsTheNameOrder() {
        #expect(FirmwareOrder.name.sorted(byName).map(\.id) == ["a", "b", "c", "d"])
    }

    @Test func putsTheNewestReleaseFirstAndUndatedLast() {
        #expect(FirmwareOrder.updated.sorted(byName).map(\.id) == ["c", "a", "d", "b"])
    }

    /// The Firmware Hub's counts, and after them, by name, the firmwares it doesn't count.
    @Test func putsTheMostInstalledFirstAndUncountedLast() {
        let counts = ["a": 12, "c": 900, "d": 12]
        let entries = byName.map { entry in
            var entry = entry
            entry.installs = counts[entry.id]
            return entry
        }
        let sorted = FirmwareOrder.installs.sorted(entries)
        #expect(sorted.map(\.id) == ["c", "a", "d", "b"])
        #expect(FirmwareOrder.installs.firstUncounted(in: sorted) == "b")
        #expect(FirmwareOrder.name.firstUncounted(in: sorted) == nil)
        // With no counts at all, there's nothing to set apart.
        #expect(FirmwareOrder.installs.firstUncounted(in: byName) == nil)
    }
}
