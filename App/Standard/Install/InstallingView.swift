import SwiftUI

/// The install, from start to finish, over the whole app: what's happening, how far it's got, and
/// how it ended.
///
/// It can't be swiped away while the FM-1 is being written to.
struct InstallingView: View {
    @Environment(AppModel.self) private var model
    @State private var tracker = InstallProgress.Tracker()

    var body: some View {
        if let job = model.device.job {
            ScrollView {
                VStack(spacing: 22) {
                    FM1Drawing(
                        line1: job.current.name.uppercased(),
                        line2: screenLine(job),
                        progress: job.isRunning ? tracker.current.fraction : nil,
                        screenTint: Color(rgb: 0xFFB27A)
                    )
                    .padding(.top, 40)
                    switch job.phase {
                    case .succeeded(let reported):
                        InstallDoneView(job: job, reported: reported)
                    case .failed(let message, let canResume):
                        InstallProblemView(job: job, message: message, canResume: canResume)
                    default:
                        running(job)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.ground.ignoresSafeArea())
            .accessibilityAddTraits(.isModal)
            .onChange(of: job, initial: true) { _, job in
                withAnimation(Motion.standard) { tracker.update(with: job) }
            }
            .sensoryFeedback(trigger: job.phase) { _, phase in
                switch phase {
                case .succeeded: .success
                case .failed: .error
                default: nil
                }
            }
        }
    }

    private func screenLine(_ job: DeviceController.FlashJob) -> String {
        switch job.phase {
        case .succeeded: "Hello!"
        case .failed(_, let canResume): canResume ? "Waiting…" : "Stopped"
        default: "\(tracker.current.stage.name)…"
        }
    }

    @ViewBuilder private func running(_ job: DeviceController.FlashJob) -> some View {
        VStack(spacing: 6) {
            Text("Installing \(job.current.name)")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text(
                job.steps.count > 1
                    ? "Step \(job.index + 1) of \(job.steps.count). Keep it plugged in."
                    : "Keep it plugged in. Nearly there."
            )
            .foregroundStyle(Palette.secondaryInk)
            .contentTransition(.opacity)
        }
        ProgressBar(fraction: tracker.current.fraction)
            .accessibilityLabel("Installing")
            .accessibilityValue("\(Int(tracker.current.fraction * 100)) percent")
        StageList(current: tracker.current.stage)
        Text(keepOpenMessage)
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            .multilineTextAlignment(.center)
    }

    private var keepOpenMessage: String {
        #if os(macOS)
            "Your Mac won't sleep while this runs. If it stops for any reason, you can carry on where it left off."
        #else
            """
            Your \(ThisDevice.name) stays awake while this runs. If it stops for any reason, you can carry on \
            where it left off.
            """
        #endif
    }
}

/// One bar that springs forwards to each new value.
struct ProgressBar: View {
    var fraction: Double
    var colour = Palette.accent

    var body: some View {
        Capsule()
            .fill(Palette.control)
            .frame(height: 10)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(colour)
                        .frame(width: max(10, geometry.size.width * min(max(fraction, 0), 1)))
                }
            }
            .animation(Motion.standard, value: fraction)
            .accessibilityElement()
    }
}

/// The four stages, ticked off as they pass.
private struct StageList: View {
    var current: InstallProgress.Stage

    var body: some View {
        VStack(spacing: 0) {
            ForEach(InstallProgress.Stage.allCases) { stage in
                let isDone = stage.rawValue < current.rawValue
                let isNow = stage == current
                HStack(spacing: 12) {
                    ZStack {
                        if isDone {
                            Circle().fill(Palette.good)
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.white)
                        } else {
                            Circle().strokeBorder(isNow ? Palette.accent : Palette.line, lineWidth: isNow ? 3 : 2)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(stage.name)
                        .font(isNow ? .body.weight(.semibold) : .body)
                        .foregroundStyle(isDone || isNow ? Palette.ink : Palette.secondaryInk)
                    Spacer()
                    if isNow {
                        Text("Now").font(.footnote).foregroundStyle(Palette.secondaryInk)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityValue(isDone ? "Done" : isNow ? "Now" : "")
            }
        }
        .padding(.vertical, 4)
        .cardBackground()
        .animation(Motion.standard, value: current)
    }
}
