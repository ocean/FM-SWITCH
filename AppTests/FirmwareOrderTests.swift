import Testing

@testable import FMSwitch

/// The firmware list's orders: by name, or the newest release first.
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
}
