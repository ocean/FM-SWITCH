@_spi(Testing) import FM1Kit
import Foundation
import Testing

@testable import FMSwitch

/// What the app says before, and after, installing a firmware that takes two installs to come back
/// from once the FM-1's bootloader has been changed.
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
        #expect(message.hasSuffix("Install MIDIMON 0.4 or LOOM-8 first, then \(item.name)."))
        #expect(setup.controller.job?.needsAStepFirst == true)
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
        #expect(setup.controller.job?.needsAStepFirst == false)
    }
}
