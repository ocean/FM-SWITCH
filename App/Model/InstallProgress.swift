/// One progress value for a whole install, across its steps and phases, with the plain-words
/// stage it's at.
///
/// FM1Kit reports each phase from 0 on its own, and whether a loader checks what it wrote isn't
/// known until it starts, so the phases get fixed shares of each step and ``Tracker`` holds the
/// value so it never goes backwards.
struct InstallProgress: Equatable {
    /// What's happening, in the words the install screen uses.
    enum Stage: Int, CaseIterable, Identifiable {
        case gettingReady
        case installing
        case checking
        case restarting

        var id: Int { rawValue }

        var name: String {
            switch self {
            case .gettingReady: "Getting ready"
            case .installing: "Installing"
            case .checking: "Checking"
            case .restarting: "Restarting"
            }
        }
    }

    /// From 0 to 1 across every step.
    var fraction: Double
    var stage: Stage

    /// Where each phase starts and ends within one step.
    private static let staging = 0.0...0.1
    private static let waiting = 0.1...0.12
    private static let writing = 0.12...0.85
    private static let checking = 0.85...0.97
    private static let restarting = 0.97...1.0

    init(fraction: Double, stage: Stage) {
        self.fraction = fraction
        self.stage = stage
    }

    /// The progress of `job` as it is now, before ``Tracker`` stops it going backwards.
    init(_ job: DeviceController.FlashJob) {
        let (within, stage) = Self.position(of: job.phase)
        let steps = Double(max(job.steps.count, 1))
        fraction = min(max((Double(job.index) + within) / steps, 0), 1)
        self.stage = stage
    }

    /// How far through one step `phase` is, and its stage.
    private static func position(of phase: DeviceController.FlashPhase) -> (Double, Stage) {
        switch phase {
        case .preparing:
            (staging.lowerBound, .gettingReady)
        case .staging(let requests):
            (point(in: staging, at: Double(requests) / 75), .gettingReady)
        case .waitingForLoader:
            (point(in: waiting, at: 0.5), .gettingReady)
        case .writing(let fraction):
            (point(in: writing, at: fraction), .installing)
        case .verifying(let fraction):
            (point(in: checking, at: fraction), .checking)
        case .rebooting:
            (point(in: restarting, at: 0.5), .restarting)
        case .succeeded:
            (1, .restarting)
        case .failed:
            (0, .gettingReady)
        }
    }

    private static func point(in range: ClosedRange<Double>, at fraction: Double) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * min(max(fraction, 0), 1)
    }

    /// Keeps the progress of one install from going backwards, as the stages' fixed shares can
    /// (a loader that doesn't check jumps from writing to restarting, which is fine, but a resumed
    /// write restarts its phase from 0).
    struct Tracker: Equatable {
        private(set) var current = InstallProgress(fraction: 0, stage: .gettingReady)

        /// Takes the job's latest progress, keeping the furthest point reached.
        ///
        /// A failed job keeps where it stopped.
        mutating func update(with job: DeviceController.FlashJob) {
            if case .failed = job.phase { return }
            let next = InstallProgress(job)
            if next.fraction >= current.fraction {
                current = next
            } else if next.stage.rawValue > current.stage.rawValue {
                current.stage = next.stage
            }
        }
    }
}
