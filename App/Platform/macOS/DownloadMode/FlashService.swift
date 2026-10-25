import FM1Kit
import FM1Rescue
import Foundation

/// Reads and writes an FM-1's flash in download mode: through the privileged helper for a real
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

/// The privileged helper, over XPC.
final class HelperFlashService: FlashService, @unchecked Sendable {
    private let connection: NSXPCConnection
    private let receiver = ProgressReceiver()

    init() {
        connection = NSXPCConnection(machServiceName: FlashHelper.serviceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: (any FlashHelperProtocol).self)
        connection.exportedInterface = NSXPCInterface(with: (any FlashProgressProtocol).self)
        connection.exportedObject = receiver
        // Only FM-SWITCH's own helper, signed by the same team.
        if let requirement = FlashHelper.requirement(forIdentifier: FlashHelper.serviceName) {
            connection.setCodeSigningRequirement(requirement)
        }
        connection.resume()
    }

    deinit {
        connection.invalidate()
    }

    func read(progress: @escaping @Sendable (Double) -> Void) async throws -> FlashReading {
        receiver.handler = progress
        defer { receiver.handler = nil }
        let (result, failure): (Data?, Data?) = try await call { helper, reply in helper.readFlash { reply(($0, $1)) } }
        return try Self.decode(FlashReading.self, result, failure)
    }

    func plan(_ request: FlashRequest) async throws -> FlashPlanSummary {
        let message = try JSONEncoder().encode(request)
        let (result, failure): (Data?, Data?) = try await call { helper, reply in
            helper.plan(message) { reply(($0, $1)) }
        }
        return try Self.decode(FlashPlanSummary.self, result, failure)
    }

    func write(progress: @escaping @Sendable (Double) -> Void) async throws {
        receiver.handler = progress
        defer { receiver.handler = nil }
        let failure: Data? = try await call { helper, reply in helper.write(reply: reply) }
        if let failure { throw Self.failure(failure) }
    }

    func close() async {
        let _: Void? = try? await call { helper, reply in helper.close { reply(()) } }
    }

    /// Calls the helper, waiting for its reply, or throws when it can't be reached.
    private func call<Reply: Sendable>(
        _ body: @escaping (any FlashHelperProtocol, @escaping @Sendable (Reply) -> Void) -> Void
    ) async throws -> Reply {
        try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(
                    throwing: FlashFailure(
                        .helperUnavailable,
                        "FM-SWITCH's helper didn't answer (\(error.localizedDescription)). Nothing was written."))
            }
            guard let helper = proxy as? any FlashHelperProtocol else {
                continuation.resume(throwing: FlashFailure(.helperUnavailable, "FM-SWITCH's helper can't be reached."))
                return
            }
            body(helper) { continuation.resume(returning: $0) }
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ result: Data?, _ failure: Data?) throws -> Value
    {
        if let result, let value = try? JSONDecoder().decode(type, from: result) { return value }
        throw Self.failure(failure ?? Data())
    }

    private static func failure(_ data: Data) -> FlashFailure {
        (try? JSONDecoder().decode(FlashFailure.self, from: data))
            ?? FlashFailure(.other, "FM-SWITCH's helper sent a reply the app couldn't read. Nothing was written.")
    }
}

/// Passes the helper's progress to whoever's waiting for it.
private final class ProgressReceiver: NSObject, FlashProgressProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedHandler: (@Sendable (Double) -> Void)?

    var handler: (@Sendable (Double) -> Void)? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    func progress(_ fraction: Double) {
        handler?(fraction)
    }
}
