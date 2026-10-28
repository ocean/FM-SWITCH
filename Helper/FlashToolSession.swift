import FM1Rescue
import Foundation

/// The tool's one FM-1: reads, plans and writes it as the app asks, until the app lets go.
final class FlashToolSession {
    private let line: FlashLine
    private let work = FlashWork { try USBDownloadModeConnection.open() }
    /// The last progress sent, so the app isn't sent every small step.
    private var lastSent = -1.0

    init(line: FlashLine) {
        self.line = line
    }

    /// Answers the app's commands until it says close or goes away, then lets go of the FM-1.
    func run() -> Never {
        while let command = try? line.receive(FlashCommand.self) {
            if case .close = command { break }
            // An app that's gone can't be told; the next receive notices.
            try? line.send(answer(command))
        }
        work.close()
        try? line.send(FlashEvent.done)
        exit(0)
    }

    private func answer(_ command: FlashCommand) -> FlashEvent {
        do {
            switch command {
            case .read: return .reading(try work.read(progress: report))
            case .plan(let request): return .summary(try work.plan(request))
            case .write:
                try work.write(progress: report)
                return .done
            case .close: return .done
            }
        } catch {
            return .failure(FlashFailure(error))
        }
    }

    /// Sends the app how far it's got, in steps of half a percent.
    private func report(_ fraction: Double) {
        guard fraction == 0 || fraction >= 1 || abs(fraction - lastSent) >= 0.005 else { return }
        lastSent = fraction
        try? line.send(FlashEvent.progress(fraction))
    }
}
