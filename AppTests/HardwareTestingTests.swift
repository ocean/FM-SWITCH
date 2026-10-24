import Testing

@testable import FMSwitch

/// Which firmwares count as tested on a real FM-1.
struct HardwareTestingTests {
    @Test func countsTheFirmwareHubAndTheOfficialFirmwareAsTested() {
        #expect(CatalogueEntry(id: "sloop", name: "SLOOP", listing: [.hub, .editor]).isHardwareTested)
        #expect(CatalogueEntry(id: "official", name: "Official", listing: [], isOfficial: true).isHardwareTested)
    }

    @Test func countsFirmwaresOnFM1EditorAsTested() {
        #expect(CatalogueEntry(id: "fm1-editor-baud-girl", name: "Baud Girl", listing: .editor).isHardwareTested)
        #expect(
            CatalogueEntry(id: "fm1-editor-zeta", name: "Zeta", listing: [.editor, .resourceHub]).isHardwareTested
        )
    }

    @Test func marksFirmwaresOnlyInTheResourceHubAsUntested() {
        #expect(!CatalogueEntry(id: "resource-hub-zeta", name: "Zeta", listing: .resourceHub).isHardwareTested)
    }
}
