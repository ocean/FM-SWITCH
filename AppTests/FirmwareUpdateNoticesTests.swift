import Testing

@testable import FMSwitch

/// What a notification about saved firmwares' updates says.
@MainActor
struct FirmwareUpdateNoticesTests {
    @Test func namesOneFirmwareAndItsVersion() {
        let entry = CatalogueEntry(id: "estampie", name: "ESTAMPIE", version: "0.3.8", listing: .hub)
        let content = FirmwareUpdateNotices.content(for: [entry])
        #expect(content.title == "ESTAMPIE 0.3.8 is out")
        #expect(content.userInfo["firmware"] as? String == "estampie")
    }

    @Test func namesSeveralFirmwares() {
        let entries = [
            CatalogueEntry(id: "estampie", name: "ESTAMPIE", version: "0.3.8", listing: .hub),
            CatalogueEntry(id: "melodee", name: "Melodee", version: "1.6.0", listing: .hub),
        ]
        let content = FirmwareUpdateNotices.content(for: entries)
        #expect(content.title == "2 saved firmwares have updates")
        #expect(content.body == "ESTAMPIE and Melodee.")
        #expect(content.userInfo.isEmpty)
    }
}
