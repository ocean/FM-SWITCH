import FM1Kit
import Foundation
import Testing

@testable import FMSwitch

/// Save my FM-1 through the app's own controller and backup store, against the simulated FM-1.
@MainActor
@Suite(.serialized)
struct BackupTests {
    private static func store() -> BackupStore {
        BackupStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
    }

    @Test func savesAnOpenFirmwareFM1() async throws {
        let setup = try await FlashingTests.setUp { $0.simulatedOpenFirmware = true }
        let store = Self.store()
        #expect(setup.controller.identity == SimulatedOpenFirmware.identity)

        await setup.controller.backUp(into: store)

        guard case .succeeded(let saved) = setup.controller.backupRun else {
            Issue.record("The backup didn't finish: \(setup.controller.backupRun)")
            return
        }
        #expect(saved.projectNames == ["Night Drive", "Bassline", "Choir Pad"])
        #expect(saved.sampleBytes == 48_000)
        #expect(saved.identity == "FM-1_8000012")
        #expect(store.backups == [saved])
        let files = try FileManager.default.contentsOfDirectory(atPath: saved.folder.path).sorted()
        #expect(
            files == ["backup.json", "samples.fm1s", "slot-01.fm1", "slot-02.fm1", "slot-05.fm1", "workspace.fm1"])
        // The FM-1 is back on the project it was on, unsaved changes and all.
        #expect(setup.controller.simulatedDevice?.currentWorkspace == SimulatedOpenFirmware.project(4))
        #expect(setup.controller.simulatedDevice?.currentSlot == 0)
        #expect(!setup.controller.isWriting)
    }

    @Test func refusesOtherFirmwaresAndSavesNothing() async throws {
        let setup = try await FlashingTests.setUp()
        let store = Self.store()

        await setup.controller.backUp(into: store)

        guard case .failed(let message) = setup.controller.backupRun else {
            Issue.record("A firmware other than open firmware was backed up: \(setup.controller.backupRun)")
            return
        }
        #expect(message.contains("open firmware"))
        #expect(store.backups.isEmpty)
    }

    @Test func keepsEachSaveInAFolderOfItsOwn() async throws {
        let setup = try await FlashingTests.setUp { $0.simulatedOpenFirmware = true }
        let store = Self.store()

        await setup.controller.backUp(into: store)
        setup.controller.dismissBackup()
        await setup.controller.backUp(into: store)

        #expect(store.backups.count == 2)
        #expect(Set(store.backups.map(\.folder)).count == 2)
        let first = try #require(store.backups.last)
        try store.delete(first)
        #expect(store.backups.count == 1)
        #expect(!FileManager.default.fileExists(atPath: first.folder.path))
    }

    @Test func zipsASaveToShareIt() async throws {
        let setup = try await FlashingTests.setUp { $0.simulatedOpenFirmware = true }
        let store = Self.store()
        await setup.controller.backUp(into: store)
        let saved = try #require(store.backups.first)

        let zip = try BackupArchive(backup: saved).zipped()

        let bytes = try Data(contentsOf: zip)
        #expect(bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]))
    }

    @Test func describesWhatWasSaved() {
        let folder = URL.temporaryDirectory
        let withSamples = SavedBackup(
            folder: folder, date: .now, identity: "FM-1_8000012", projectNames: ["A"], sampleBytes: 48_000)
        #expect(withSamples.contentsLine.hasPrefix("1 project, the project you were working on, and your samples ("))
        let without = SavedBackup(
            folder: folder, date: .now, identity: "FM-1_8000012", projectNames: ["A", "B"], sampleBytes: nil)
        #expect(without.contentsLine == "2 projects and the project you were working on")
    }
}
