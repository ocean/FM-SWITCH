import FM1Rescue
import Foundation

/// One FM-1 in download mode: reads its flash, plans a write against what was read, and writes
/// it.
///
/// The helper runs one for the app over USB, as root; the app runs one itself over a simulated
/// FM-1. It isn't safe to share between threads, so each keeps it on one queue.
final class FlashWork {
    private let connect: () throws -> any DownloadModeConnection
    private var session: FlashSession?
    private var current: FlashBackup?
    private var pending: FlashPlan?

    /// - Parameter connect: Opens the FM-1 in download mode, when it's first needed.
    init(connect: @escaping () throws -> any DownloadModeConnection) {
        self.connect = connect
    }

    /// Reads the whole flash twice, checked against the chip's CRC-32, and keeps it to plan
    /// against.
    ///
    /// Nothing is written.
    ///
    /// - Parameter progress: Called with the share read so far.
    /// - Returns: The backup, and what's on it.
    /// - Throws: A ``DownloadModeError``.
    func read(progress: (Double) -> Void) throws -> FlashReading {
        pending = nil
        current = nil
        let backup: FlashBackup
        do {
            backup = try openSession().backUp(progress: progress)
        } catch {
            // A connection that failed part-way is opened again next time.
            close()
            throw error
        }
        current = backup
        return try FlashReading(backup)
    }

    /// Plans `request` against the flash last read, and keeps the plan to write.
    ///
    /// - Throws: ``FlashFailure`` when the flash hasn't been read, or any error planning.
    func plan(_ request: FlashRequest) throws -> FlashPlanSummary {
        guard let current else { throw FlashFailure(.other, "Read the FM-1's flash first. Nothing was written.") }
        pending = nil
        let plan = try request.plan(onto: current)
        pending = plan
        return FlashPlanSummary(plan)
    }

    /// Writes the plan last made, checking every change against the chip's CRC-32.
    ///
    /// - Parameter progress: Called with the share written so far.
    /// - Throws: ``FlashFailure`` when there's no plan, or a ``DownloadModeError``.
    func write(progress: (Double) -> Void) throws {
        guard let plan = pending, let session else {
            throw FlashFailure(.other, "There's nothing planned to write. Nothing was written.")
        }
        // The flash changes, so a new plan needs it read again.
        pending = nil
        current = nil
        try session.write(plan, progress: progress)
    }

    /// Lets go of the FM-1.
    ///
    /// It stays in download mode until it's switched off and on.
    func close() {
        session?.close()
        session = nil
        current = nil
        pending = nil
    }

    private func openSession() throws -> FlashSession {
        if let session { return session }
        let opened = try FlashSession(connection: connect())
        session = opened
        return opened
    }
}
