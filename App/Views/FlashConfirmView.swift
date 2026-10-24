import FM1Kit
import SwiftUI

/// Shows exactly what will be flashed (including any official-first step) before starting, and
/// asks for confirmation when that switches the FM-1 to a different firmware, or installs the
/// identity its custom firmware already reports.
struct FlashConfirmView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var checked = InstallCheckState.checking
    @State private var backedUp = false
    @State private var acceptsUntested = false
    let target: StoredFirmware
    var requiresOfficial = false
    var onStart: () -> Void = {}

    var body: some View {
        let readiness = InstallReadiness(
            target: target, requiresOfficial: requiresOfficial, checked: checked, model: model)
        let steps = readiness.steps
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(
                title: readiness.isSwitching
                    ? "SWITCH FIRMWARE?" : readiness.isSameIdentity ? "REINSTALL OR UPDATE?" : "FLASH?")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        MonoText("\(index + 1). \(step.name) \(step.version)", size: 17)
                    }
                    if readiness.isMissingOfficial {
                        MonoText(
                            "This needs the official firmware first, and none is saved. Add it under SAVED.", size: 14)
                    }
                    if readiness.isUntested {
                        MonoText("IN TESTING. \(InstallReadiness.untestedWarning)", size: 14)
                        PixelToggle("I'LL TRY IT WHILE IT'S IN TESTING", isOn: $acceptsUntested)
                    }
                    deviceNotes(firstStep: steps.first)
                    checkNotes(switching: readiness.isSwitching)
                    NoteText("Takes a minute or two per step. Stay in the app until it finishes.")
                }
            }
            .scrollIndicators(.hidden)
            buttons(readiness)
        }
        .padding(20)
        .overlay { CRTOverlay() }
        .task(id: "\(steps.first?.id ?? "")|\(model.device.identity?.text ?? "")") {
            checked = .checking
            checked = await InstallReadiness.check(steps.first, on: model.device)
        }
    }

    /// CANCEL, and the button that starts: SWITCH, INSTALL for the same identity, or START.
    private func buttons(_ readiness: InstallReadiness) -> some View {
        HStack(spacing: 10) {
            Button("CANCEL") { dismiss() }
                .buttonStyle(.pixel)
            // Starting from the REINSTALL OR UPDATE? question is the confirmation it asks for.
            Button(readiness.isSwitching ? "SWITCH" : readiness.isSameIdentity ? "INSTALL" : "START") {
                model.device.flash(
                    readiness.steps,
                    confirmsSwitchingFirmware: readiness.isSwitching && backedUp,
                    confirmsSameIdentity: readiness.isSameIdentity
                )
                dismiss()
                onStart()
            }
            .buttonStyle(.pixelProminent)
            .disabled(!readiness.canStart(confirmsSwitch: backedUp, acceptsUntested: acceptsUntested))
        }
    }

    /// What the FM-1 reports now, and whether the first step can finish an update it's waiting in.
    @ViewBuilder private func deviceNotes(firstStep: StoredFirmware?) -> some View {
        if let identity = model.device.identity {
            MonoText("THE FM-1 NOW REPORTS \(identity.text)", size: 13, dim: true)
            if identity.isLoader, let first = firstStep,
                !model.library.packages(thatCanFinish: identity).contains(first)
            {
                MonoText(
                    """
                    The FM-1 is in an update another package started, and \(first.name) can't finish it. \
                    Flash the firmware you were installing instead.
                    """,
                    size: 14
                )
            }
        } else {
            MonoText("No FM-1 is connected yet. Connect it before starting.", size: 14)
        }
    }

    /// What the check found: a reinstall, a switch or the same identity to confirm, or why it
    /// couldn't check.
    @ViewBuilder private func checkNotes(switching: Bool) -> some View {
        switch checked {
        case .checking where model.device.identity != nil:
            MonoText("CHECKING THE FM-1…", size: 13, dim: true)
        case .failed(let reason):
            MonoText(reason, size: 14)
        case .found(.reinstall) where !switching:
            MonoText("The FM-1 is already running this firmware, so there's nothing to install.", size: 14)
        case .found(.sameIdentity) where !switching:
            if let identity = model.device.identity {
                MonoText(
                    """
                    The FM-1 already reports \(identity.text), the same as this package. Installing it \
                    reinstalls that firmware, or updates it to this release.
                    """,
                    size: 14
                )
            }
        default:
            EmptyView()
        }
        if switching {
            MonoText(
                """
                This switches the FM-1 to a different firmware. That can erase its projects, sounds and \
                samples, so back up anything you want to keep first.
                """,
                size: 14
            )
            PixelToggle("I'VE BACKED UP WHAT I NEED", isOn: $backedUp)
        } else {
            NoteText("Back up the FM-1's projects, sounds and samples before changing its firmware.")
        }
    }
}
