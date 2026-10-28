import FM1Kit
import FM1Rescue
import Foundation
import Observation
import UniformTypeIdentifiers

/// What to do with an FM-1 in the chip's download mode.
enum DownloadModeJob: Hashable {
    /// Reads and saves the whole flash.
    case backUp
    /// Puts a whole-flash backup back.
    case restore(SavedFlashBackup)
    /// Installs a saved firmware straight to the flash, keeping the bootloader.
    case install(StoredFirmware, erasingSettings: Bool)
    /// Installs m-bootloader 1.2, which comes with the app.
    case mBootloader
    /// Puts back M-VAVE's bootloader, from V15's package.
    case mvaveBootloader

    /// What it does, as a heading.
    var title: String {
        switch self {
        case .backUp: "Back up the whole FM-1"
        case .restore: "Restore a backup"
        case .install(let firmware, _): "Install \(firmware.name)"
        case .mBootloader: "Install m-bootloader"
        case .mvaveBootloader: "Put back M-VAVE's bootloader"
        }
    }

    /// Whether it writes to the FM-1, rather than only reading it.
    var writes: Bool { self != .backUp }
}

/// The Mac's download-mode tools: whole-flash backups, restoring them, and installing firmware
/// or a bootloader straight to the flash, which works even when the FM-1's firmware won't start.
///
/// Every job reads the whole flash and saves it first. A write is planned against that read,
/// shown, and only made once the person confirms it. A real FM-1 is read and written by the
/// flash tool, which needs root; the simulated one, by FM1Rescue's software chip in the app.
@MainActor
@Observable
final class DownloadModeController {
    /// Where the job is up to.
    enum Phase: Equatable {
        case idle
        case reading(Double)
        /// Read and saved, with a write planned and waiting to be confirmed.
        case confirming(FlashPlanSummary, saved: SavedFlashBackup)
        case writing(Double, saved: SavedFlashBackup)
        /// A backup's done.
        case backedUp(SavedFlashBackup)
        /// The FM-1 already holds what was asked for.
        case nothingToWrite(SavedFlashBackup)
        /// A write's done and checked.
        case written(saved: SavedFlashBackup)
        /// It stopped; `saved` is the backup made first, if it got that far.
        case failed(FlashFailure, saved: SavedFlashBackup?)

        var isRunning: Bool {
            switch self {
            case .reading, .writing: true
            default: false
            }
        }
    }

    /// A backup's `.bin` file, as FM1Kit and M-Flasher save it.
    static let backupType = UTType(filenameExtension: "bin") ?? .data

    private(set) var job: DownloadModeJob?
    private(set) var phase = Phase.idle
    /// Whether an FM-1 is in download mode now.
    private(set) var isInDownloadMode = false
    /// Whether the app is asking the FM-1 to restart into download mode.
    private(set) var isEntering = false
    /// Why the FM-1 didn't restart into download mode, when it didn't.
    private(set) var enteringProblem: String?

    /// Whether m-bootloader was on the FM-1 when it was last read.
    private(set) var hadMBootloader = false

    let backups: FlashBackupStore
    private let library: FirmwareLibrary
    private let device: DeviceController
    private let isSimulated: @MainActor () -> Bool
    private var service: (any FlashService)?
    /// The simulated FM-1's flash, kept so what's written to it stays.
    private var simulatedFlash: SimulatedFlash?
    private var simulatedInDownloadMode = false

    init(
        library: FirmwareLibrary,
        device: DeviceController,
        backupsFolder: @escaping @MainActor () -> URL,
        isSimulated: @escaping @MainActor () -> Bool
    ) {
        self.library = library
        self.device = device
        self.isSimulated = isSimulated
        backups = FlashBackupStore(backupsFolder: backupsFolder)
    }

    /// Whether the connected FM-1 can be asked to restart into download mode, which any firmware
    /// running on it can do.
    var canAskToEnter: Bool {
        guard let identity = device.identity, !identity.isLoader else { return false }
        return !device.isWriting
    }

    // MARK: - Download mode.

    /// Checks for an FM-1 in download mode every second until cancelled.
    func watch() async {
        while !Task.isCancelled {
            isInDownloadMode =
                isSimulated() ? simulatedInDownloadMode : USBDownloadModeConnection.deviceCount() > 0
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Asks the connected FM-1 to restart into download mode, and waits for it to appear there.
    func enterDownloadMode() async {
        guard !isEntering else { return }
        isEntering = true
        enteringProblem = nil
        defer { isEntering = false }
        if isSimulated() {
            try? await Task.sleep(for: .seconds(1))
            simulatedInDownloadMode = true
            isInDownloadMode = true
            return
        }
        do {
            try await device.enterDownloadMode()
            isInDownloadMode = true
        } catch {
            enteringProblem = error.localizedDescription
        }
    }

    /// Leaves the simulated FM-1's download mode, as switching a real one off and on does.
    func leaveSimulatedDownloadMode() {
        simulatedInDownloadMode = false
        isInDownloadMode = false
    }

    // MARK: - Jobs.

    /// Reads and saves the whole flash, then, for a write, plans it and waits for ``confirm()``.
    func start(_ job: DownloadModeJob) async {
        guard !phase.isRunning else { return }
        self.job = job
        phase = .reading(0)
        await closeService()
        let service: any FlashService
        do {
            service = try await makeService()
        } catch {
            phase = .failed(FlashFailure(error), saved: nil)
            return
        }
        self.service = service

        let saved: SavedFlashBackup
        do {
            let reading = try await withProgress(
                showing: { self.phase = .reading($0) },
                running: { try await service.read(progress: $0) })
            saved = try backups.save(reading.files)
            hadMBootloader = reading.hasMBootloader
        } catch {
            await fail(error, saved: nil)
            return
        }
        guard job.writes else {
            phase = .backedUp(saved)
            await closeService()
            return
        }
        do {
            let plan = try await service.plan(request(for: job))
            if plan.isEmpty {
                phase = .nothingToWrite(saved)
                await closeService()
            } else {
                phase = .confirming(plan, saved: saved)
            }
        } catch {
            await fail(error, saved: saved)
        }
    }

    /// Writes the planned change, checking every part of it.
    func confirm() async {
        guard case .confirming(_, let saved) = phase, let service else { return }
        phase = .writing(0, saved: saved)
        do {
            try await withProgress(
                showing: { self.phase = .writing($0, saved: saved) },
                running: { try await service.write(progress: $0) })
            phase = .written(saved: saved)
            await closeService()
        } catch {
            await fail(error, saved: saved)
        }
    }

    /// Copies a backup from elsewhere, such as M-Flasher, and its `.json` if it's beside it, in
    /// with the other backups, then restores it.
    func restoreImported(_ url: URL) async throws {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let saved = try backups.save(FlashFiles(contentsOf: url))
        await start(.restore(saved))
    }

    /// Puts the backup made before a failed write back.
    func restoreAfterFailure() async {
        guard case .failed(_, let saved?) = phase else { return }
        await start(.restore(saved))
    }

    /// Ends the job, writing nothing more.
    ///
    /// The FM-1 stays in download mode until it's switched off and on.
    func finish() async {
        guard !phase.isRunning else { return }
        job = nil
        phase = .idle
        await closeService()
    }

    private func fail(_ error: any Error, saved: SavedFlashBackup?) async {
        let failure = FlashFailure(error)
        phase = .failed(failure, saved: saved)
        await closeService()
    }

    private func closeService() async {
        await service?.close()
        service = nil
    }

    private func makeService() async throws -> any FlashService {
        guard isSimulated() else { return ToolFlashService() }
        if simulatedFlash == nil, let official = library.official {
            simulatedFlash = SimulatedFlash(holding: try await library.loadPackage(official))
        }
        guard let simulatedFlash, simulatedInDownloadMode else {
            throw FlashFailure(.notFound, "The simulated FM-1 isn't in download mode. Nothing was written.")
        }
        return SimulatedFlashService(flash: simulatedFlash)
    }

    /// What to plan for `job`.
    private func request(for job: DownloadModeJob) async throws -> FlashRequest {
        switch job {
        case .backUp:
            throw FlashFailure(.other, "A backup doesn't write anything.")
        case .restore(let backup):
            return .restore(try await backups.files(of: backup))
        case .install(let firmware, let erasingSettings):
            return .firmware(try await packageData(firmware), erasingSettings: erasingSettings)
        case .mBootloader:
            return .mBootloader(try Self.mBootloaderData())
        case .mvaveBootloader:
            guard let official = library.official else {
                throw FlashFailure(.other, "M-VAVE's V15 isn't in the app, so its bootloader can't be put back.")
            }
            return .packageBootloader(try await packageData(official))
        }
    }

    private func packageData(_ firmware: StoredFirmware) async throws -> Data {
        let url = library.url(for: firmware)
        try await SharedStorage.download(url)
        return try Data(contentsOf: url)
    }

    /// m-bootloader 1.2's `fm1-uboot.boot`, which comes with the app, checked against its
    /// release's SHA-256.
    static func mBootloaderData() throws -> Data {
        guard let url = Bundle.main.url(forResource: "fm1-uboot", withExtension: "boot"),
            let data = try? Data(contentsOf: url),
            FwscPackage.sha256Hex([UInt8](data)) == mBootloaderSHA256
        else {
            throw FlashFailure(.other, "The app's copy of m-bootloader is missing or damaged. Nothing was written.")
        }
        return data
    }

    /// The SHA-256 of m-bootloader 1.2's `fm1-uboot.boot`, from its release's `SHA256SUMS`.
    static let mBootloaderSHA256 = "9e5ec0e39dc55c167f8e289cfdac612d7d340b5f46100e1be2540ef4d6ec2f13"

    /// Runs `body`, passing it a progress handler that reaches `update` on the main actor.
    private func withProgress<Value: Sendable>(
        showing update: @escaping @MainActor (Double) -> Void,
        running body: (@escaping @Sendable (Double) -> Void) async throws -> Value
    ) async throws -> Value {
        let (fractions, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let consumer = Task { @MainActor in
            for await fraction in fractions { update(fraction) }
        }
        let result: Result<Value, any Error>
        do {
            result = .success(try await body { continuation.yield($0) })
        } catch {
            result = .failure(error)
        }
        // The last update lands before the caller moves on, so it can't overwrite what comes next.
        continuation.finish()
        await consumer.value
        return try result.get()
    }
}
