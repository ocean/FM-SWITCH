import FM1Kit
import FM1Rescue
import Foundation

/// Reads and writes an FM-1's flash in download mode: through the flash tool for a real
/// FM-1, or in the app for the simulated one.
protocol FlashService: AnyObject, Sendable {
    /// Reads the whole flash, twice, checked against the chip's CRC-32. Nothing is written.
    func read(progress: @escaping @Sendable (Double) -> Void) async throws -> FlashReading
    /// Plans a change against the flash last read.
    func plan(_ request: FlashRequest) async throws -> FlashPlanSummary
    /// Writes the plan last made, checking every change.
    func write(progress: @escaping @Sendable (Double) -> Void) async throws
    /// Lets go of the FM-1, which stays in download mode until it's switched off and on.
    func close() async
}

/// The simulated FM-1's flash, kept between download-mode sessions as a real FM-1's is.
///
/// Each session gets a chip of its own, as closing one ends it.
final class SimulatedFlash: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [UInt8]
    private var chip: SimulatedDownloadMode?

    /// A simulated FM-1 holding `official`, as a new one does.
    ///
    /// - Parameter official: V15's package, installed with M-VAVE's bootloader.
    init(holding official: FwscPackage) {
        let chip = SimulatedDownloadMode()
        // The chip starts with patterned flash; V15 goes on as a factory would put it.
        if let session = try? FlashSession(connection: chip),
            let blank = try? session.backUp(),
            let plan = try? FlashPlan.installing(official, onto: blank, includingBootloader: true)
        {
            try? session.write(plan)
        }
        stored = chip.flash
    }

    /// A chip for a new session, holding the flash as the last one left it.
    func connect() -> SimulatedDownloadMode {
        lock.withLock {
            if let chip { stored = chip.flash }
            let next = SimulatedDownloadMode(flash: stored)
            chip = next
            return next
        }
    }
}

/// The simulated FM-1 in download mode, run in the app: FM1Rescue's software chip.
final class SimulatedFlashService: FlashService, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.drewr.fmswitch.simulated-flash")
    private let work: FlashWork

    init(flash: SimulatedFlash) {
        work = FlashWork { flash.connect() }
    }

    func read(progress: @escaping @Sendable (Double) -> Void) async throws -> FlashReading {
        try await run { try $0.read(progress: progress) }
    }

    func plan(_ request: FlashRequest) async throws -> FlashPlanSummary {
        try await run { try $0.plan(request) }
    }

    func write(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await run { try $0.write(progress: progress) }
    }

    func close() async {
        try? await run { $0.close() }
    }

    private func run<Result: Sendable>(_ body: @escaping @Sendable (FlashWork) throws -> Result) async throws -> Result
    {
        let work = UncheckedWork(work: work)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Swift.Result { try body(work.work) })
            }
        }
    }
}

/// The simulated FM-1's ``FlashWork``, passed to its queue, where only it's used.
private struct UncheckedWork: @unchecked Sendable {
    var work: FlashWork
}

/// The flash tool, started as root with the person's administrator password, over its pipe.
///
/// It's started when first needed and quits when closed, so each job asks for the password,
/// though macOS doesn't ask again within a few minutes.
final class ToolFlashService: FlashService, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.drewr.fmswitch.flash-tool")
    private let lock = NSLock()
    private var storedLine: FlashLine?

    func read(progress: @escaping @Sendable (Double) -> Void) async throws -> FlashReading {
        try await exchange(.read, progress: progress) { event in
            if case .reading(let reading) = event { reading } else { nil }
        }
    }

    func plan(_ request: FlashRequest) async throws -> FlashPlanSummary {
        try await exchange(.plan(request)) { event in
            if case .summary(let summary) = event { summary } else { nil }
        }
    }

    func write(progress: @escaping @Sendable (Double) -> Void) async throws {
        do {
            try await exchange(.write, progress: progress) { event in
                if case .done = event { () } else { nil }
            }
        } catch let failure as FlashFailure {
            throw failure
        } catch {
            // The tool went part-way through, so the flash may be half-written.
            throw FlashFailure(
                .writeFailed, "FM-SWITCH's flash tool stopped while writing (\(error.localizedDescription)).")
        }
    }

    func close() async {
        guard line != nil else { return }
        let _: Void? = try? await exchange(.close) { _ in () }
        lock.withLock { storedLine = nil }
    }

    private var line: FlashLine? { lock.withLock { storedLine } }

    /// Sends `command`, passing on progress, until the tool answers with what `answer` picks out.
    private func exchange<Value: Sendable>(
        _ command: FlashCommand,
        progress: (@Sendable (Double) -> Void)? = nil,
        _ answer: @escaping @Sendable (FlashEvent) -> Value?
    ) async throws -> Value {
        let line = try await connected()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(
                    with: Result {
                        try line.send(command)
                        while true {
                            let event = try line.receive(FlashEvent.self)
                            if case .progress(let fraction) = event {
                                progress?(fraction)
                            } else if case .failure(let failure) = event {
                                throw failure
                            } else if let value = answer(event) {
                                return value
                            } else {
                                throw FlashFailure(
                                    .other, "FM-SWITCH's flash tool answered out of turn. Nothing was written.")
                            }
                        }
                    })
            }
        }
    }

    /// The pipe to the tool, starting it first if it isn't running.
    private func connected() async throws -> FlashLine {
        if let line { return line }
        let line: FlashLine = try await withCheckedThrowingContinuation { continuation in
            // Asking for the password waits for the person, so not on the main thread.
            queue.async {
                continuation.resume(with: Result { try ToolLauncher.start() })
            }
        }
        lock.withLock { storedLine = line }
        return line
    }

    static let didntStart = "FM-SWITCH's flash tool didn't start. Nothing was written."

    static let passwordPrompt = "FM-SWITCH needs your password to read and write the FM-1's flash."
    static let cancelled = "Reading the FM-1 needs your administrator password. Nothing was read or written."
}
