@_spi(Testing) import FM1Kit
import Foundation
import Testing

@testable import FMSwitch

/// What the app says before, and after, installing a firmware that only a Mac can come back from
/// once m-bootloader is on the FM-1.
@MainActor
@Suite(.serialized)
struct StartUpTests {
    @Test func theAnswerIsRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let settings = AppSettings(defaults: defaults)
        #expect(settings.startUp == nil)

        settings.startUp = .mBootloader
        #expect(AppSettings(defaults: defaults).startUp == .mBootloader)
        settings.startUp = nil
        #expect(AppSettings(defaults: defaults).startUp == nil)
    }

    @Test func onlyKnownFirmwaresAreFlagged() {
        #expect(FeluccaUpdateCode.isKnown("amb"))
        #expect(FeluccaUpdateCode.isKnown("melodee"))
        #expect(!FeluccaUpdateCode.isKnown("fm1-editor-estampie"))
        #expect(!FeluccaUpdateCode.isKnown("mvave-official"))
        #expect(!FeluccaUpdateCode.isKnown("zp12"))
        #expect(!FeluccaUpdateCode.isKnown(nil))
    }

    @Test func aPackageThatAcceptsV15IsntFlagged() async throws {
        let library = FirmwareLibrary(
            directory: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let item = try FlashingTests.save("FM-1_015", in: library)
        #expect(await !InstallReadiness.refusesV15OverOtherBootloaders(item, in: library))
    }

    @Test func theWarningNamesTheOthersAndHedgesWhenUnsure() {
        let sure = FeluccaUpdateCode.Warning(installing: "amb", named: "AMB-1", startUp: .mBootloader)
        #expect(sure.body.hasPrefix("Once AMB-1 is on your FM-1"))
        #expect(sure.body.contains("(DUB-1, Felucca, HYP-1, LOF-1 and Melodee)"))
        #if os(macOS)
            #expect(sure.body.hasSuffix("you'll need Backup & rescue."))
        #else
            #expect(sure.body.hasSuffix("you'll need FM-SWITCH on a Mac."))
        #endif

        let unsure = FeluccaUpdateCode.Warning(installing: "dub", named: "DUB-1", startUp: .notSure)
        #expect(unsure.body.hasPrefix("If your FM-1's bootloader has been changed, once DUB-1 is on your FM-1"))
        #expect(unsure.body.contains("AMB-1"))
        #expect(!unsure.body.contains("DUB-1,"))
    }

    @Test func aRefusedInstallIsExplainedPlainly() async throws {
        let setup = try await FlashingTests.setUp { $0.simulatedMBootloader = true }
        let item = try FlashingTests.save("FM-1_015", in: setup.library)

        setup.controller.flash([item], confirmsSwitchingFirmware: true)
        try await FlashingTests.waitUntil(seconds: 90) { setup.controller.job?.isRunning == false }

        guard case .failed(let message, _) = setup.controller.job?.phase else {
            Issue.record("The install wasn't refused: \(String(describing: setup.controller.job?.phase)).")
            return
        }
        #expect(message.hasPrefix("Your FM-1 is fine. It's still running the firmware it had"))
        #if os(macOS)
            #expect(message.hasSuffix("use Backup & rescue."))
        #else
            #expect(message.hasSuffix("use FM-SWITCH on a Mac."))
        #endif
        #expect(setup.controller.job?.needsAMac == true)
        #expect(setup.controller.identity?.text == "FM-1_900")
    }

    @Test func aStallBeforeTheInstallStartsMightBeARefusal() {
        #expect(DeviceController.FlashJob.mightBeRefused(after: FM1UpdateError.stalled(phase: .staging, requests: 2)))
        #expect(!DeviceController.FlashJob.mightBeRefused(after: FM1UpdateError.stalled(phase: .writing, requests: 9)))
        #expect(!DeviceController.FlashJob.mightBeRefused(after: FM1UpdateError.bootloaderMismatch(requests: 3)))
    }

    @Test func bothRefusalsAreRecognised() {
        #expect(DeviceController.FlashJob.isRefusal(FM1UpdateError.bootloaderMismatch(requests: 3)))
        #expect(DeviceController.FlashJob.isRefusal(FM1UpdateError.packageRefused(requests: 2)))
        #expect(!DeviceController.FlashJob.isRefusal(FM1UpdateError.stalled(phase: .staging, requests: 2)))
    }

    @Test func aRefusalWithMVavesStartUpSuggestsV15First() async throws {
        let setup = try await FlashingTests.setUp { settings in
            settings.simulatedMBootloader = true
            settings.startUp = .mVave
        }
        let item = try FlashingTests.save("FM-1_8000012", in: setup.library)

        setup.controller.flash([item], confirmsSwitchingFirmware: true)
        try await FlashingTests.waitUntil(seconds: 90) { setup.controller.job?.isRunning == false }

        guard case .failed(let message, _) = setup.controller.job?.phase else {
            Issue.record("The install wasn't refused: \(String(describing: setup.controller.job?.phase)).")
            return
        }
        #expect(message.contains("from here. Install V15 first, then"))
        #expect(!message.contains("m-bootloader"))
        #expect(setup.controller.job?.needsAMac == false)
    }
}
