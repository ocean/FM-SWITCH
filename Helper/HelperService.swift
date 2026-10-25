import FM1Rescue
import Foundation

/// Accepts connections from the app, each with its own FM-1 session, and quits once none has
/// been open for ``idleLimit``.
final class HelperListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var connections = 0
    private var lastClosed = Date()

    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let service = HelperService(connection: connection)
        connection.exportedInterface = NSXPCInterface(with: (any FlashHelperProtocol).self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: (any FlashProgressProtocol).self)
        connection.invalidationHandler = { [weak self] in
            service.close {}
            self?.closed()
        }
        lock.withLock { connections += 1 }
        connection.resume()
        return true
    }

    /// Quits once no app has been connected for ``idleLimit``; launchd starts it again when one
    /// connects.
    func quitIfIdle() {
        DispatchQueue.global().asyncAfter(deadline: .now() + idleLimit / 4) { [self] in
            let isIdle = lock.withLock { connections == 0 && Date().timeIntervalSince(lastClosed) >= idleLimit }
            if isIdle { exit(0) }
            quitIfIdle()
        }
    }

    private func closed() {
        lock.withLock {
            connections -= 1
            lastClosed = Date()
        }
    }
}

/// One app connection's FM-1: reads, plans and writes on a queue of its own, one at a time.
final class HelperService: NSObject, FlashHelperProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.drewr.fmswitch.helper.flash")
    private let work = FlashWork { try USBDownloadModeConnection.open() }
    private weak var connection: NSXPCConnection?
    /// The last progress sent, so the app isn't sent every small step.
    private var lastSent = -1.0

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func readFlash(reply: @escaping @Sendable (Data?, Data?) -> Void) {
        queue.async { [self] in
            do {
                let reading = try work.read(progress: report)
                reply(JSONEncoder.flashMessage(reading), nil)
            } catch {
                reply(nil, JSONEncoder.flashMessage(FlashFailure(error)))
            }
        }
    }

    func plan(_ request: Data, reply: @escaping @Sendable (Data?, Data?) -> Void) {
        queue.async { [self] in
            do {
                let summary = try work.plan(JSONDecoder().decode(FlashRequest.self, from: request))
                reply(JSONEncoder.flashMessage(summary), nil)
            } catch {
                reply(nil, JSONEncoder.flashMessage(FlashFailure(error)))
            }
        }
    }

    func write(reply: @escaping @Sendable (Data?) -> Void) {
        queue.async { [self] in
            do {
                try work.write(progress: report)
                reply(nil)
            } catch {
                reply(JSONEncoder.flashMessage(FlashFailure(error)))
            }
        }
    }

    func close(reply: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            work.close()
            reply()
        }
    }

    /// Sends the app how far it's got, in steps of half a percent.
    private func report(_ fraction: Double) {
        guard fraction == 0 || fraction >= 1 || abs(fraction - lastSent) >= 0.005 else { return }
        lastSent = fraction
        (connection?.remoteObjectProxy as? any FlashProgressProtocol)?.progress(fraction)
    }
}
