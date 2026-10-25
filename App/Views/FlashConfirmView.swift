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
    /// Whether to ask what starts the FM-1, decided once as it opens so the question stays while
    /// it's answered.
    @State private var asksStartUp = false
    @State private var usesFeluccaUpdateCode = false
    @State private var showsWhy = false
    let target: StoredFirmware
    var requiresOfficial = false
    var onStart: () -> Void = {}

    var body: some View {
        let readiness = InstallReadiness(
            target: target,
            requiresOfficial: requiresOfficial,
            checked: checked,
            usesFeluccaUpdateCode: usesFeluccaUpdateCode,
            model: model)
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
                    startUp(readiness)
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
            usesFeluccaUpdateCode = await InstallReadiness.usesFeluccaUpdateCode(target, in: model.library)
            asksStartUp = asksStartUp || (usesFeluccaUpdateCode && model.settings.startUp != .mVave)
            checked = await InstallReadiness.check(steps.first, on: model.device)
        }
    }

    /// What starts the FM-1, when this firmware's install depends on it, and what that means.
    @ViewBuilder private func startUp(_ readiness: InstallReadiness) -> some View {
        if asksStartUp {
            MonoText(StartUp.question.uppercased(), size: 14)
            NoteText(StartUp.questionDetail)
            ForEach(StartUp.allCases) { choice in
                StartUpChoice(choice: choice, startUp: Bindable(model.settings).startUp)
            }
            NoteText(StartUp.changeLater)
        }
        if let warning = readiness.macWarning {
            MonoText("! \(warning.title.uppercased())", size: 14)
            MonoText(warning.body, size: 14)
            PixelToggle("WHY?", isOn: $showsWhy)
            if showsWhy { NoteText(warning.why) }
        }
    }

    /// CANCEL, and the button that starts: SWITCH, INSTALL for the same identity, or START.
    private func buttons(_ readiness: InstallReadiness) -> some View {
        HStack(spacing: 10) {
            Button(readiness.macWarning?.keep.uppercased() ?? "CANCEL") { dismiss() }
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

/// One answer to what starts the FM-1, picked by tapping anywhere on it.
struct StartUpChoice: View {
    @Environment(\.phosphor) private var theme
    var choice: StartUp
    @Binding var startUp: StartUp?

    var body: some View {
        Button {
            startUp = choice
        } label: {
            HStack(alignment: .top) {
                Text(startUp == choice ? "(●)" : "( )")
                    .font(.mono(17))
                    .foregroundStyle(theme.bright)
                VStack(alignment: .leading, spacing: 2) {
                    MonoText(choice.name.uppercased(), size: 14)
                    if let detail = choice.detail { NoteText(detail) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(startUp == choice ? [.isSelected] : [])
    }
}
