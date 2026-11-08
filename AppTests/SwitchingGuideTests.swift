@_spi(Testing) import FM1Kit
import Foundation
import Testing

@testable import FMSwitch

/// How the app works out the way to switch away from each firmware, from FM1Kit's guides, and
/// what it saves with each install.
@MainActor
@Suite(.serialized)
struct SwitchingGuideTests {
    private static let transit = LeavingGuide(
        firmwareName: "TransitFM1", identity: .officialV15, updateCode: .ownLoader, bootArea: .mBootloader)
    private static let felucca = LeavingGuide(
        firmwareName: "Felucca",
        identity: FM1Identity(model: "FM-1", version: 916),
        updateCode: .feluccaOriginalCheck,
        bootArea: nil
    )

    private static func officialPackage() throws -> FwscPackage {
        let url = try #require(FirmwareLibrary.bundledOfficialURL)
        return try FwscPackage(data: Data(contentsOf: url))
    }

    // MARK: - What's running.

    @Test func mVavesFirmwaresAreKnownByTheirIdentity() {
        let v15 = SwitchingGuide.running(.officialV15, saved: nil, startUp: nil)
        #expect(v15?.updateCode == .mVave)
        #expect(v15?.bootArea == .v15)
        #expect(SwitchingGuide.running(.officialV16, saved: nil, startUp: .mVave)?.bootArea == .v16)
        // Installed in download mode, which keeps m-bootloader.
        #expect(SwitchingGuide.running(.officialV15, saved: nil, startUp: .mBootloader)?.bootArea == .mBootloader)
    }

    @Test func aSavedGuideTellsTransitFM1FromV15() {
        let running = SwitchingGuide.running(.officialV15, saved: Self.transit, startUp: .mVave)
        #expect(running == Self.transit)
        #expect(running.map(SwitchingGuide.reportsOfficialIdentity) == true)
        #expect(running?.route(to: .v15) == .direct)
        #expect(running?.route(to: .v16) == .throughFixedFirmware)
    }

    @Test func aSavedGuideForAnotherIdentityIsIgnored() {
        #expect(
            SwitchingGuide.running(FM1Identity(model: "FM-1", version: 916), saved: Self.transit, startUp: nil) == nil)
    }

    @Test func theStartUpFillsInABootloaderTheGuideDoesntKnow() {
        let filled = SwitchingGuide.running(Self.felucca.identity, saved: Self.felucca, startUp: .mBootloader)
        #expect(filled?.bootArea == .mBootloader)
        #expect(filled?.route(to: .v15) == .throughFixedFirmware)
        #expect(SwitchingGuide.running(Self.felucca.identity, saved: Self.felucca, startUp: .notSure)?.bootArea == nil)
    }

    @Test func nothingIsKnownAboutAnUpdateLoaderOrAnUnknownFirmware() {
        #expect(SwitchingGuide.running(FM1Identity(text: "ota-FM-1_015"), saved: nil, startUp: .mVave) == nil)
        #expect(SwitchingGuide.running(FM1Identity(model: "FM-1", version: 916), saved: nil, startUp: .mVave) == nil)
        #expect(SwitchingGuide.running(nil, saved: nil, startUp: .mVave) == nil)
    }

    @Test func startUpsAndBootloadersMatch() {
        for startUp in StartUp.allCases {
            guard let bootArea = startUp.bootArea else {
                #expect(startUp == .notSure)
                continue
            }
            #expect(StartUp(bootArea) == startUp)
        }
    }

    // MARK: - What's going on.

    @Test func v15IsADestinationOfItsOwn() throws {
        let package = try Self.officialPackage()
        #expect(LeavingDestination(installing: package) == .v15)
        let custom = try FwscPackage(data: FwscPackage.sampleFile(product: "FM-1_916"))
        #expect(LeavingDestination(installing: custom) == .feluccaPlatform)
    }

    @Test func installingV15BringsItsBootloaderAndChangesTheStartUp() throws {
        let package = try Self.officialPackage()
        let running = SwitchingGuide.filling(Self.felucca, from: .mBootloader)
        let installed = SwitchingGuide.installing(package, named: "V15", over: running, startUp: .mBootloader)
        #expect(installed.guide?.bootArea == .v15)
        #expect(installed.startUp == .mVave)
    }

    @Test func v15ThroughTransitFM1KeepsTheBootloader() throws {
        let package = try Self.officialPackage()
        let installed = SwitchingGuide.installing(package, named: "V15", over: Self.transit, startUp: .mBootloader)
        #expect(installed.guide?.bootArea == .mBootloader)
        #expect(installed.startUp == nil)
    }

    // MARK: - Warnings.

    @Test func anUnknownBootloaderGivesTheWarningsForAChangedOne() {
        var check = SwitchingCheck(isRead: true)
        check.installed = Self.felucca
        #expect(check.warnings.count == 1)
        #expect(check.warnings[0].hasPrefix(SwitchingCheck.ifChanged))

        check.installed = SwitchingGuide.filling(Self.felucca, from: .mBootloader)
        #expect(check.warnings.count == 1)
        #expect(check.warnings[0].hasPrefix("Once Felucca is installed"))

        // With V15's bootloader, only V16 brings one it refuses.
        check.installed = SwitchingGuide.filling(Self.felucca, from: .mVave)
        #expect(check.warnings.count == 1)
        #expect(check.warnings[0].contains("can't install V16 straight away"))
    }

    @Test func transitFM1WarnsAboutV16AndItsIdentity() {
        var check = SwitchingCheck(isRead: true)
        check.installed = Self.transit
        #expect(check.warnings.count == 2)
        #expect(check.warnings.contains { $0.contains("reports itself as V15") })
    }

    // MARK: - Refusals.

    @Test func aRefusalNeedsMIDIMONUnlessTheFirmwareRunningTakesV15() {
        let refused = FM1UpdateError.bootloaderMismatch(requests: 3)
        let item = StoredFirmware(
            id: "a",
            name: "LOOM",
            version: "1",
            product: "FM-1_8000012",
            sha256: "a",
            size: 1,
            fileName: "a.fwsc",
            source: .catalogue,
            savedAt: .now
        )
        let fromFelucca = SwitchingGuide.filling(Self.felucca, from: .mBootloader)
        #expect(
            DeviceController.FlashJob.needsAStepFirst(
                after: refused, installing: item, from: fromFelucca, startUp: .mVave))
        #expect(
            !DeviceController.FlashJob.needsAStepFirst(
                after: refused, installing: item, from: Self.transit, startUp: nil))
        #expect(
            !DeviceController.FlashJob.needsAStepFirst(after: refused, installing: item, from: nil, startUp: .mVave))

        let message = DeviceController.FlashJob.failureMessage(
            for: refused, installing: item, running: "Felucca", needsAStepFirst: true)
        #expect(message.hasPrefix("Your FM-1 is fine. It's still running Felucca, which won't take LOOM from here."))
        #expect(message.hasSuffix(" Install MIDIMON 0.4 or LOOM-8 first, then LOOM."))
    }

    // MARK: - Choosing a device.

    @Test func aChosenDeviceIsFoundAgainAfterRestarting() {
        func device(_ id: String, _ version: Int, serial: String? = nil) -> FM1DeviceSummary {
            FM1DeviceSummary(
                identity: FM1Identity(model: "FM-1", version: version),
                port: MIDIPortDescriptor(id: id, name: "FM-1", serialNumber: serial))
        }
        let chosen = device("1", 900, serial: "A1")
        #expect(DeviceChoice.same(chosen, in: [device("2", 15), device("1", 900)], identity: nil)?.id == "1")
        #expect(
            DeviceChoice.same(chosen, in: [device("3", 15), device("4", 916, serial: "A1")], identity: nil)?.id == "4")
        let unnamed = device("1", 900)
        let found = [device("5", 15), device("6", 916)]
        #expect(DeviceChoice.same(unnamed, in: found, identity: FM1Identity(model: "FM-1", version: 916))?.id == "6")
        #expect(DeviceChoice.same(unnamed, in: found, identity: nil) == nil)
    }

    // MARK: - Installing.

    @Test func anInstallSavesItsGuide() async throws {
        let setup = try await FlashingTests.setUp()
        let item = try FlashingTests.save("FM-1_916", in: setup.library)

        setup.controller.flash([item], confirmsSwitchingFirmware: true)
        try await FlashingTests.waitUntil(seconds: 90) { setup.controller.job?.isRunning == false }

        #expect(setup.controller.job?.phase == .succeeded("FM-1_916"))
        let guide = try #require(setup.history.last?.guide)
        #expect(guide.identity.text == "FM-1_916")
        #expect(guide.firmwareName == item.name)
        #expect(setup.controller.runningGuide == guide)
    }

    @Test func installingV15SetsMVavesStartUp() async throws {
        let setup = try await FlashingTests.setUp { $0.startUp = .mBootloader }
        let official = try #require(setup.library.official)

        setup.controller.flash([official], confirmsSwitchingFirmware: true)
        try await FlashingTests.waitUntil(seconds: 120) { setup.controller.job?.isRunning == false }

        #expect(setup.controller.job?.phase == .succeeded(FM1Identity.officialV15.text))
        #expect(setup.history.last?.guide?.bootArea == .v15)
        #expect(setup.controller.settings?.startUp == .mVave)
    }

    @Test func installsOnTheFM1ChosenOfTwo() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let settings = AppSettings(defaults: defaults)
        settings.simulatedSecondFM1 = true
        let library = FirmwareLibrary(directory: directory)
        let controller = DeviceController(library: library, history: FlashHistory(defaults: defaults))
        controller.configure(.simulated, settings: settings)
        try await FlashingTests.waitUntil(seconds: 10) { controller.devices.count == 2 }

        #expect(controller.needsChoice)
        #expect(controller.identity == nil)
        let first = try #require(controller.devices.first { $0.identity.text == "FM-1_900" })
        let v15 = try #require(controller.devices.first { $0.identity == .officialV15 })
        controller.choose(first)
        #expect(controller.identity?.text == "FM-1_900")

        let item = try FlashingTests.save("FM-1_916", in: library)
        controller.flash([item], confirmsSwitchingFirmware: true)
        try await FlashingTests.waitUntil(seconds: 90) { controller.job?.isRunning == false }

        #expect(controller.job?.phase == .succeeded("FM-1_916"))
        let pair = try #require(controller.transport as? SimulatedPair)
        #expect(pair.device(on: v15.port).events.isEmpty)
        await controller.scan()
        #expect(controller.chosenDevice?.identity.text == "FM-1_916")
        #expect(controller.devices.contains { $0.identity == .officialV15 })
    }
}
