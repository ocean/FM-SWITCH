import FM1Kit
import os

/// Passes on an install's events as FM1Kit reports them, but only the progress that moves the
/// bar, so the main actor isn't asked to redraw for each of the loader's thousands of reads and
/// fall behind the FM-1.
///
/// It also times the loader's last read when it happens, for the log.
final class InstallEventFilter: Sendable {
    /// The smallest change of a phase's progress that's passed on.
    static let step = 0.005

    private struct State {
        /// The last progress passed on: its phase and fraction.
        var shown: (phase: Int, fraction: Double)?
        var lastRead: ContinuousClock.Instant?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// `event` to pass on, with how long ago the loader last read the image when it's
    /// `rebooting`, or `nil` for progress too small to show.
    func filter(_ event: UpdateEvent) -> (event: UpdateEvent, quiet: Duration?)? {
        let now = ContinuousClock.now
        return state.withLock { state in
            guard let (phase, fraction) = Self.progress(of: event) else {
                let quiet = event == .rebooting ? state.lastRead.map { now - $0 } : nil
                return (event, quiet)
            }
            state.lastRead = now
            if let shown = state.shown, shown.phase == phase, fraction < 1, abs(fraction - shown.fraction) < Self.step {
                return nil
            }
            state.shown = (phase, fraction)
            return (event, nil)
        }
    }

    /// Which progress phase `event` is in (writing, the second pass or the resources) and how
    /// far through it, or `nil` for any other event.
    private static func progress(of event: UpdateEvent) -> (Int, Double)? {
        switch event {
        case .writing(let fraction, _): (0, fraction)
        case .checking(let fraction, _): (1, fraction)
        case .writingResources(let fraction, _): (2, fraction)
        default: nil
        }
    }
}
