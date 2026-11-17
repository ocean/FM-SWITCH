import FM1Kit
import Foundation
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

    @Test func picksOutFirmwaresOnlyTheirMakersList() {
        #expect(CatalogueEntry(id: "mutant-cloud-zeta", name: "Zeta", listing: .mutantCloud).isListedOnlyByItsMaker)
        #expect(
            !CatalogueEntry(id: "zeta", name: "Zeta", listing: [.mutantCloud, .resourceHub]).isListedOnlyByItsMaker)
        #expect(!CatalogueEntry(id: "sloop", name: "SLOOP", listing: [.mutantCloud, .hub]).isListedOnlyByItsMaker)
    }

    @Test func leavesOutPackagesForOtherDevices() {
        #expect(OtherDevices.isPackage("kayak-1.3-smk37-elite.fwsc"))
        #expect(OtherDevices.isPackage("speak37-mke-1.0.fwsc"))
        #expect(OtherDevices.isPackage("saadet-smk37-pro-1.0.5.fwsc"))
        #expect(!OtherDevices.isPackage("kayak-1.3.fwsc"))
        #expect(!OtherDevices.isPackage("x0x-1.0.6-probe-320.fwsc"))

        func build(_ name: String, _ file: String) -> CatalogueEntry.Build {
            CatalogueEntry.Build(name: name, url: URL(filePath: "/\(file)"))
        }
        var fune = CatalogueEntry(id: "fune", name: "Fune", listing: .mutantCloud)
        fune.packageURL = URL(filePath: "/fune-smk37-pro.fwsc")
        fune.builds = [build("fm1", "fune-fm1.fwsc"), build("smk37-pro", "fune-smk37-pro.fwsc")]
        let forTheFM1 = fune.onlyForTheFM1()
        #expect(forTheFM1.packageURL?.lastPathComponent == "fune-fm1.fwsc")
        #expect(forTheFM1.builds == nil)
    }

    @Test func knowsAnSMK37ByWhatItReports() {
        // FM1Kit doesn't parse an identity with a space, such as "SMK-37 Elite_016", so the app knows
        // those SMK-37s by their USB port instead.
        for text in ["MKE-P37_1100", "ota-MKE-P37_900"] {
            #expect(InstallReadiness.isOtherDevice(FM1Identity(text: text)), "\(text)")
        }
        for text in ["FM-1_016", "ota-FM-1_900", "FM-1_11000100"] {
            #expect(!InstallReadiness.isOtherDevice(FM1Identity(text: text)), "\(text)")
        }
        for name in ["Melodee SMK-37", "MKE-P37", "SMK-37 Elite"] {
            #expect(OtherDevices.isNamed(name), "\(name)")
        }
        #expect(!OtherDevices.isNamed("FM-1"))
    }
}
