import FM1Kit
import Foundation
import Testing

@testable import FMSwitch

/// Catching an install that finished without FM1Kit seeing it, and saving each install's log.
@MainActor
struct InstallFinishTests {
    typealias FlashJob = DeviceController.FlashJob

    @Test func looksAgainWhenTheFM1DidNotReturn() {
        #expect(FlashJob.mightHaveFinished(after: FM1UpdateError.deviceDidNotReturn, written: 1, reinstalling: false))
        #expect(FlashJob.mightHaveFinished(after: FM1UpdateError.deviceDidNotReturn, written: 1, reinstalling: true))
    }

    @Test func looksAgainWhenTheWriteStoppedNearTheEnd() {
        let stalled = FM1UpdateError.stalled(phase: .writing, requests: 900)
        let lost = FM1UpdateError.disconnected(phase: .writing, requests: 900)
        #expect(FlashJob.mightHaveFinished(after: stalled, written: 0.97, reinstalling: false))
        #expect(FlashJob.mightHaveFinished(after: lost, written: 1, reinstalling: false))
    }

    @Test func doesNotLookAgainPartWayThrough() {
        let lost = FM1UpdateError.disconnected(phase: .writing, requests: 400)
        #expect(!FlashJob.mightHaveFinished(after: lost, written: 0.45, reinstalling: false))
    }

    /// The firmware it had reports the same identity, so finding it proves nothing.
    @Test func doesNotLookAgainForAReinstallThatStopped() {
        let stalled = FM1UpdateError.stalled(phase: .writing, requests: 900)
        #expect(!FlashJob.mightHaveFinished(after: stalled, written: 0.99, reinstalling: true))
    }

    @Test func doesNotLookAgainForOtherErrors() {
        let errors: [FM1UpdateError] = [
            .stalled(phase: .staging, requests: 10),
            .identityMismatch(expected: "FM-1_7010300", reported: "FM-1_900"),
            .loaderNotFound,
            .deviceNotFound,
        ]
        for error in errors {
            #expect(!FlashJob.mightHaveFinished(after: error, written: 1, reinstalling: false))
        }
    }

    @Test func savesTheLogAsItGoes() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let log = try #require(InstallLogFile(in: folder))
        log.append("Rebooting into the new firmware.")
        let text = try String(contentsOf: log.url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("FM-SWITCH"))
        #expect(lines[1].hasSuffix("Rebooting into the new firmware."))
        #expect(lines[1].hasPrefix("+"))
    }

    @Test func keepsOnlyTheNewestLogs() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var newest: URL?
        for minute in 0...InstallLogFile.kept {
            newest = InstallLogFile(in: folder, date: start + Double(minute) * 60)?.url
        }
        let logs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        #expect(logs.count == InstallLogFile.kept)
        #expect(logs.map(\.lastPathComponent).contains(try #require(newest).lastPathComponent))
    }
}
