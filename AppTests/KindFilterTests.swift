import Testing

@testable import FMSwitch

/// The list's filters by kind, taken from the lists as they are.
struct KindFilterTests {
    private let entries = [
        CatalogueEntry(id: "a", name: "A", kinds: ["synth", "groove"], listing: .hub),
        CatalogueEntry(id: "b", name: "B", kinds: ["Synth"], listing: .hub),
        CatalogueEntry(id: "c", name: "C", kinds: ["drums"], listing: .hub),
        CatalogueEntry(id: "d", name: "D", listing: .editor),
    ]

    @Test func listsEachKindOnceTheMostCommonFirst() {
        #expect(FirmwareFilter.kinds(of: entries) == ["synth", "drums", "groove"])
    }

    @Test func matchesAKindWhateverItsCase() {
        #expect(entries.filter { FirmwareFilter.isKind("synth", $0) }.map(\.id) == ["a", "b"])
    }

    @Test func namesKindsAsTheFirmwareHubDoes() {
        #expect(FirmwareFilter.name(of: "groove") == "Grooveboxes")
        #expect(FirmwareFilter.name(of: "platform") == "Platform")
    }
}
