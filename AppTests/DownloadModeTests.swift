#if os(macOS)
    import Foundation
    import Testing

    @testable import FMSwitch

    /// The Mac's download-mode jobs, end to end through the app's controller, against FM1Rescue's
    /// simulated chip holding V15 with M-VAVE's bootloader.
    @MainActor
    @Suite(.serialized)
    struct DownloadModeTests {
        private let library: FirmwareLibrary
        private let tools: DownloadModeController

        init() async throws {
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
            library = FirmwareLibrary(directory: folder.appending(path: "Firmwares"))
            let device = DeviceController(library: library, history: FlashHistory(defaults: defaults))
            tools = DownloadModeController(
                library: library,
                device: device,
                backupsFolder: { folder.appending(path: "Backups") },
                isSimulated: { true })
        }

        @Test func backsUpTheWholeFlashAndSavesItWithItsDescription() async throws {
            await tools.enterDownloadMode()
            await tools.start(.backUp)
            guard case .backedUp(let saved) = tools.phase else {
                Issue.record("Expected a backup, got \(tools.phase)")
                return
            }
            #expect(saved.firmware == "V15 (FM-1_015)")
            #expect(saved.bootloader == "M-VAVE's")
            #expect(tools.backups.backups == [saved])
            #expect(try Data(contentsOf: saved.file).count == 0x10_0000)
        }

        /// Installs m-bootloader, then puts the backup made first back, which takes M-VAVE's
        /// bootloader back too.
        @Test func installsMBootloaderThenRestoresTheBackupFromBefore() async throws {
            await tools.enterDownloadMode()
            await tools.start(.mBootloader)
            guard case .confirming(let plan, let before) = tools.phase else {
                Issue.record("Expected a plan, got \(tools.phase)")
                return
            }
            #expect(plan.writesBootArea)
            #expect(!plan.isEmpty)
            await tools.confirm()
            #expect(tools.phase == .written(saved: before))

            await tools.start(.backUp)
            guard case .backedUp(let after) = tools.phase else {
                Issue.record("Expected a backup, got \(tools.phase)")
                return
            }
            #expect(after.bootloader?.hasPrefix("m-bootloader 1.2") == true)

            await tools.start(.restore(before))
            guard case .confirming(let restore, _) = tools.phase else {
                Issue.record("Expected a plan, got \(tools.phase)")
                return
            }
            #expect(restore.writesBootArea)
            await tools.confirm()
            await tools.start(.backUp)
            guard case .backedUp(let restored) = tools.phase else {
                Issue.record("Expected a backup, got \(tools.phase)")
                return
            }
            #expect(restored.bootloader == "M-VAVE's")
        }

        @Test func writesNothingWhenTheFirmwareIsAlreadyThere() async throws {
            let official = try #require(library.official)
            await tools.enterDownloadMode()
            await tools.start(.install(official, erasingSettings: false))
            guard case .nothingToWrite = tools.phase else {
                Issue.record("Expected nothing to write, got \(tools.phase)")
                return
            }
        }

        @Test func keepsOneBackupOfTheSameFlash() async throws {
            await tools.enterDownloadMode()
            await tools.start(.backUp)
            guard case .backedUp(let first) = tools.phase else {
                Issue.record("Expected a backup, got \(tools.phase)")
                return
            }
            await tools.finish()
            await tools.start(.restore(first))
            guard case .nothingToWrite(let saved) = tools.phase else {
                Issue.record("Expected nothing to write, got \(tools.phase)")
                return
            }
            #expect(saved == first)
            #expect(tools.backups.backups == [first])
        }

        @Test func waitsForDownloadModeBeforeReading() async {
            await tools.start(.backUp)
            guard case .failed(let failure, nil) = tools.phase else {
                Issue.record("Expected it to stop, got \(tools.phase)")
                return
            }
            #expect(failure.kind == .notFound)
            #expect(tools.backups.backups.isEmpty)
        }

        @Test func comesWithMBootloader() throws {
            #expect(try DownloadModeController.mBootloaderData().count == 12_936)
        }

        @Test func carriesABackupBetweenTheHelperAndTheApp() async throws {
            await tools.enterDownloadMode()
            await tools.start(.backUp)
            guard case .backedUp(let saved) = tools.phase else {
                Issue.record("Expected a backup, got \(tools.phase)")
                return
            }
            let files = try FlashFiles(contentsOf: saved.file)
            let decoded = try JSONDecoder().decode(FlashFiles.self, from: JSONEncoder().encode(files))
            #expect(try decoded.backup().sha256 == files.backup().sha256)
        }
    }
#endif
