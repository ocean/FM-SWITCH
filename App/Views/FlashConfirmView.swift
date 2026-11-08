import FM1Kit
import SwiftUI

/// Shows exactly what will be flashed (including any official-first step) before starting, and
/// asks for confirmation when that switches the FM-1 to a different firmware, or installs the
/// identity its custom firmware already reports.
struct FlashConfirmView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var checked = InstallCheckState.checking
    @State private var switching = SwitchingCheck()
    @State private var backedUp = false
    @State private var acceptsUntested = false
    @State private var confirmsNotOfficial = false
    /// Whether to ask what starts the FM-1, decided once as it opens so the question stays while
    /// it's answered.
    @State private var asksStartUp = false
    @State private var showsWhy = false
    let target: StoredFirmware
    var requiresOfficial = false
    var onStart: () -> Void = {}

    var body: some View {
        let readiness = InstallReadiness(
            target: target,
            requiresOfficial: requiresOfficial,
            checked: checked,
            switching: switching,
            model: model)
        let steps = readiness.steps
        let isSwitching = isSwitching(readiness)
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(
                title: isSwitching
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
                    route(readiness)
                    startUp(readiness)
                    deviceNotes(firstStep: steps.first)
                    checkNotes(readiness, switching: isSwitching)
                    NoteText(
                        """
                        Takes a minute or two per step. The FM-1's screen stays dark while it installs: keep \
                        it plugged in and switched on, and stay in the app until it finishes.
                        """
                    )
                }
            }
            .scrollIndicators(.hidden)
            buttons(readiness)
        }
        .padding(20)
        .overlay { CRTOverlay() }
        .task(id: "\(target.id)|\(model.device.identity?.text ?? "")|\(model.settings.startUp?.rawValue ?? "")") {
            switching = await SwitchingCheck.read(installing: target, requiresOfficial: requiresOfficial, model: model)
            asksStartUp = asksStartUp || (switching.dependsOnStartUp && model.settings.startUp != .mVave)
        }
        .task(id: "\(steps.first?.id ?? "")|\(model.device.identity?.text ?? "")") {
            checked = .checking
            checked = await InstallReadiness.check(steps.first, on: model.device)
        }
    }

    /// Why MIDIMON or LOOM-8 goes on first, or why the firmware running might refuse this, and
    /// what V15 does after V16.
    @ViewBuilder private func route(_ readiness: InstallReadiness) -> some View {
        let switching = readiness.switching
        let planned = readiness.steps.filter { $0 != switching.firstStep }
        if let running = switching.running, let destination = switching.destination {
            if let firstStep = switching.firstStep {
                MonoText(
                    SwitchingWords.firstStep(firstStep.name, running: running.firmwareName, next: planned[0].name),
                    size: 14)
                PixelToggle("WHY?", isOn: $showsWhy)
                if showsWhy {
                    ForEach(Array(running.instructions(to: destination).enumerated()), id: \.offset) { index, step in
                        NoteText("\(index + 1). \(step)")
                    }
                }
            } else if readiness.isMissingFirstStep {
                MonoText(
                    SwitchingWords.missingFirstStep(
                        running: running.firmwareName, next: planned[0].name, problem: switching.firstStepProblem),
                    size: 14)
            } else if switching.route == .uncertain {
                NoteText(running.instructions(to: destination).joined(separator: " "))
            }
        }
        if !switching.knowsOnlyFirstChip.isEmpty {
            MonoText("! \(InstallReadiness.newerFlashChipWarning(switching.knowsOnlyFirstChip))", size: 14)
        }
        if switching.installsV16 {
            MonoText("! \(InstallReadiness.beforeV16Warning)", size: 14)
        }
        if switching.followsV16 {
            MonoText("! \(InstallReadiness.afterV16Warning)", size: 14)
        }
    }

    /// What starts the FM-1, when this firmware's install depends on it, and what switching away
    /// from it will take.
    @ViewBuilder private func startUp(_ readiness: InstallReadiness) -> some View {
        if asksStartUp {
            MonoText(StartUp.question.uppercased(), size: 14)
            NoteText(StartUp.questionDetail)
            ForEach(StartUp.allCases) { choice in
                StartUpChoice(choice: choice, startUp: Bindable(model.settings).startUp)
            }
            NoteText(StartUp.changeLater)
        }
        if !readiness.switching.warnings.isEmpty {
            MonoText("! \(SwitchingWords.warningTitle.uppercased())", size: 14)
            ForEach(readiness.switching.warnings, id: \.self) { MonoText($0, size: 14) }
            Button("WHAT CAN I DO?") {
                model.requestedPage = .help(.wontInstall)
                dismiss()
            }
            .buttonStyle(.pixelCompact)
        }
    }

    /// Whether this switches firmware, including V15 over a firmware that only reports V15.
    private func isSwitching(_ readiness: InstallReadiness) -> Bool {
        readiness.isSwitching || (readiness.canReinstallOfficial && confirmsNotOfficial)
    }

    /// CANCEL, and the button that starts: SWITCH, INSTALL for the same identity, or START.
    private func buttons(_ readiness: InstallReadiness) -> some View {
        let isSwitching = isSwitching(readiness)
        return HStack(spacing: 10) {
            Button(readiness.switching.warnings.isEmpty ? "CANCEL" : SwitchingWords.decline.uppercased()) { dismiss() }
                .buttonStyle(.pixel)
            // Starting from the REINSTALL OR UPDATE? question is the confirmation it asks for.
            Button(isSwitching ? "SWITCH" : readiness.isSameIdentity ? "INSTALL" : "START") {
                model.device.flash(
                    readiness.steps,
                    confirmsSwitchingFirmware: isSwitching && backedUp,
                    confirmsSameIdentity: readiness.isSameIdentity,
                    confirmsReinstallingOfficial: readiness.knowsItIsntOfficial
                        || (readiness.canReinstallOfficial && confirmsNotOfficial)
                )
                dismiss()
                onStart()
            }
            .buttonStyle(.pixelProminent)
            .disabled(
                !readiness.canStart(
                    confirmsSwitch: backedUp, acceptsUntested: acceptsUntested, confirmsNotOfficial: confirmsNotOfficial
                ))
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
        } else if model.device.needsChoice {
            MonoText(DeviceChoice.chooseFirst.replacingOccurrences(of: "My FM-1", with: "DEVICE"), size: 14)
        } else {
            MonoText("No FM-1 is connected yet. Connect it before starting.", size: 14)
        }
    }

    /// What the check found: a reinstall, a switch or the same identity to confirm, or why it
    /// couldn't check.
    @ViewBuilder private func checkNotes(_ readiness: InstallReadiness, switching: Bool) -> some View {
        switch checked {
        case .checking where model.device.identity != nil:
            MonoText("CHECKING THE FM-1…", size: 13, dim: true)
        case .failed(let reason):
            MonoText(reason, size: 14)
        case .found(.reinstall) where readiness.knowsItIsntOfficial:
            if let running = readiness.switching.running, let identity = readiness.identity {
                MonoText(SwitchingWords.replacesLookAlike(running.firmwareName, reporting: identity), size: 14)
            }
        case .found(.reinstall) where readiness.canReinstallOfficial:
            if let identity = readiness.identity {
                if !confirmsNotOfficial { MonoText(SwitchingWords.alreadyOfficial(identity), size: 14) }
                PixelToggle(SwitchingWords.notReallyOfficial.uppercased(), isOn: $confirmsNotOfficial)
                NoteText(SwitchingWords.notReallyOfficialDetail(identity))
            }
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
