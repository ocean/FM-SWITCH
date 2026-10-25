import FM1Kit
import SwiftUI

/// The short checklist before installing, and the FM-1's own check of what the install will do.
struct BeforeYouStartView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var checked = InstallCheckState.checking
    @State private var hasDataCable = false
    @State private var staysPluggedIn = false
    @State private var hasSaved = false
    @State private var acceptsUntested = false
    /// Whether to ask what starts the FM-1, decided once as the sheet opens so the question stays
    /// while it's answered.
    @State private var asksStartUp = false
    @State private var usesFeluccaUpdateCode = false
    let target: StoredFirmware
    var requiresOfficial = false

    var body: some View {
        let readiness = InstallReadiness(
            target: target,
            requiresOfficial: requiresOfficial,
            checked: checked,
            usesFeluccaUpdateCode: usesFeluccaUpdateCode,
            model: model)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    plan(readiness)
                    startUp(readiness)
                    status(readiness)
                    checklist(readiness)
                }
                .padding(20)
            }
            .background(Palette.ground)
            .navigationTitle("Before you start")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { startButton(readiness) }
        }
        .tint(Palette.accentText)
        .sensoryFeedback(.selection, trigger: [hasDataCable, staysPluggedIn, hasSaved, acceptsUntested])
        .task(id: "\(readiness.steps.first?.id ?? "")|\(model.device.identity?.text ?? "")") {
            checked = .checking
            usesFeluccaUpdateCode = await InstallReadiness.usesFeluccaUpdateCode(target, in: model.library)
            asksStartUp = asksStartUp || (usesFeluccaUpdateCode && model.settings.startUp != .mVave)
            checked = await InstallReadiness.check(readiness.steps.first, on: model.device)
        }
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    /// What goes on, in order.
    @ViewBuilder private func plan(_ readiness: InstallReadiness) -> some View {
        HStack(spacing: 14) {
            FirmwareBadge(design: model.catalogue.badge(id: target.catalogueID, name: target.name))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(target.name) \(target.version)").font(.headline)
                if readiness.steps.count > 1, let first = readiness.steps.first {
                    Text("\(first.name) goes on first, as \(target.name) installs from it.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        if readiness.isMissingOfficial {
            Notice(
                "This needs M-VAVE's official firmware to go on first, and there's no copy of it here.",
                systemImage: "exclamationmark.triangle",
                isWarning: true
            )
        }
        if readiness.isUntested {
            Notice(
                "In testing. \(InstallReadiness.untestedWarning)",
                systemImage: "exclamationmark.triangle",
                isWarning: true
            )
        }
    }

    /// What starts the FM-1, when this firmware's install depends on it, and what that means.
    @ViewBuilder private func startUp(_ readiness: InstallReadiness) -> some View {
        @Bindable var settings = model.settings
        if asksStartUp {
            StartUpQuestion(startUp: $settings.startUp.animation(Motion.fade))
        }
        if let warning = readiness.macWarning {
            MacWarningCard(warning: warning)
        }
    }

    /// What the FM-1 says, and what the check found.
    @ViewBuilder private func status(_ readiness: InstallReadiness) -> some View {
        if let identity = model.device.identity {
            if identity.isLoader {
                Notice(
                    "Your FM-1 is waiting to finish an install, so this carries on with it.",
                    systemImage: "arrow.clockwise",
                    isWarning: false
                )
            }
            switch checked {
            case .checking:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking your FM-1…").foregroundStyle(Palette.secondaryInk)
                }
            case .failed(let reason):
                Notice(reason, systemImage: "exclamationmark.triangle", isWarning: true)
            case .found(.reinstall) where readiness.isAlreadyInstalled:
                Notice(
                    "Your FM-1 is already running this, so there's nothing to install.",
                    systemImage: "checkmark.circle",
                    isWarning: false
                )
            case .found(.sameIdentity) where readiness.isSameIdentity:
                Notice(
                    """
                    Your FM-1 already reports \(identity.text), the same as this. Installing it reinstalls \
                    that firmware, or updates it to this release.
                    """,
                    systemImage: "info.circle",
                    isWarning: false
                )
            default:
                EmptyView()
            }
        } else {
            Notice("Plug in your FM-1 and switch it on.", systemImage: "cable.connector", isWarning: true)
        }
    }

    @ViewBuilder private func checklist(_ readiness: InstallReadiness) -> some View {
        VStack(spacing: 0) {
            CheckRow(
                title: "It's plugged in with a data cable",
                detail: "Some USB cables only charge. If your FM-1 showed up in the app, yours is fine.",
                isOn: $hasDataCable)
            Divider().overlay(Palette.line)
            CheckRow(
                title: "I'll leave it plugged in until it's done",
                detail: "And keep the app open. If anything stops it, you can carry on where it left off.",
                isOn: $staysPluggedIn)
            if readiness.isSwitching {
                Divider().overlay(Palette.line)
                CheckRow(
                    title: "I've saved anything I want to keep",
                    detail: "Changing to a different firmware can erase the FM-1's projects, sounds and samples.",
                    isOn: $hasSaved)
            }
            if readiness.isUntested {
                Divider().overlay(Palette.line)
                CheckRow(
                    title: "I'll try it while it's in testing",
                    detail: "If it goes wrong, getting back to another firmware may take a computer.",
                    isOn: $acceptsUntested)
            }
        }
        .cardBackground()
        Text("Takes about a minute. Your FM-1 restarts on its own along the way.")
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
    }

    private func startButton(_ readiness: InstallReadiness) -> some View {
        let isTicked =
            hasDataCable && staysPluggedIn && (!readiness.isSwitching || hasSaved)
            && (!readiness.isUntested || acceptsUntested)
        let title =
            readiness.needsStartUp
            ? "Choose your FM-1's start-up" : isTicked ? "Install \(target.name)" : "Tick each one to install"
        let install = Button(title) {
            model.device.flash(
                readiness.steps,
                confirmsSwitchingFirmware: readiness.isSwitching && hasSaved,
                confirmsSameIdentity: readiness.isSameIdentity
            )
            dismiss()
        }
        .buttonStyle(.prominent(Palette.firmwares))
        .disabled(!isTicked || !readiness.canStart(confirmsSwitch: hasSaved, acceptsUntested: acceptsUntested))
        .animation(Motion.fade, value: isTicked)
        return HStack(spacing: 10) {
            // Keeping things as they are is as easy to pick as installing.
            if let warning = readiness.macWarning {
                Button(warning.keep) { dismiss() }
                    .buttonStyle(.secondary)
            }
            install
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.ground)
    }
}

/// One item on the checklist: the whole row toggles it.
private struct CheckRow: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(Motion.press) { isOn.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                    .font(.title2)
                    .foregroundStyle(isOn ? Palette.firmwaresTint : Palette.secondaryInk)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Palette.ink)
                    Text(detail).font(.subheadline).foregroundStyle(Palette.secondaryInk)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// A short message in a tinted box: a warning, or information.
struct Notice: View {
    var text: String
    var systemImage: String
    var isWarning: Bool

    init(_ text: String, systemImage: String, isWarning: Bool) {
        self.text = text
        self.systemImage = systemImage
        self.isWarning = isWarning
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(isWarning ? Palette.warningInk : Palette.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isWarning ? Palette.warningBackground : Palette.control)
            )
    }
}
