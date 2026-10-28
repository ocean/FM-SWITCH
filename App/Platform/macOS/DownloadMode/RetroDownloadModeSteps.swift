import SwiftUI

/// Says whether the FM-1 is in download mode, and how to get it there, in Retro.
struct RetroDownloadModeConnect: View {
    @Environment(AppModel.self) private var model

    private var tools: DownloadModeController { model.downloadMode }

    var body: some View {
        if tools.isInDownloadMode {
            PixelPanel(title: "DOWNLOAD MODE") {
                MonoText("✓ \(DownloadModeWords.inDownloadMode).", size: 14)
                NoteText(DownloadModeWords.inDownloadModeDetail)
                if model.settings.transportKind == .simulated {
                    Button(DownloadModeWords.leaveSimulated.uppercased()) { tools.leaveSimulatedDownloadMode() }
                        .buttonStyle(.pixelCompact)
                }
            }
        } else {
            PixelPanel(title: DownloadModeWords.enterTitle.uppercased()) {
                if tools.canAskToEnter || model.settings.transportKind == .simulated {
                    Button(
                        tools.isEntering
                            ? DownloadModeWords.askingToEnter.uppercased() : DownloadModeWords.askToEnter.uppercased()
                    ) {
                        Task { await tools.enterDownloadMode() }
                    }
                    .buttonStyle(.pixelProminent)
                    .disabled(tools.isEntering)
                    NoteText(DownloadModeWords.askToEnterDetail)
                }
                MonoText(DownloadModeWords.enterWithMBootloader, size: 14)
                MonoText(DownloadModeWords.enterWithMVave, size: 14)
                NoteText(DownloadModeWords.showsUpHere)
                if let problem = tools.enteringProblem {
                    MonoText("! \(problem)", size: 14)
                }
            }
        }
    }
}

/// The four jobs, in Retro: back up, restore, install a firmware, and install a bootloader.
struct RetroDownloadModeJobs: View {
    @Environment(AppModel.self) private var model
    @Environment(\.phosphor) private var theme
    /// Opens a file chooser for a backup from elsewhere, such as M-Flasher.
    var chooseFile: () -> Void
    @State private var firmwareID: StoredFirmware.ID?
    @State private var erasesSettings = false

    private var tools: DownloadModeController { model.downloadMode }

    var body: some View {
        PixelPanel(title: DownloadModeWords.jobsTitle.uppercased()) {
            job(DownloadModeWords.backUpTitle, DownloadModeWords.backUpDetail) {
                Button(DownloadModeWords.backUp.uppercased()) { start(.backUp) }
                    .buttonStyle(.pixelProminent)
            }
            job(DownloadModeWords.restoreTitle, DownloadModeWords.restoreDetail) {
                // Saved backups are restored from their list below.
                Button(DownloadModeWords.chooseFile.uppercased(), action: chooseFile)
                    .buttonStyle(.pixel)
            }
            job(DownloadModeWords.installTitle, DownloadModeWords.installDetail) {
                installControls
            }
            job(DownloadModeWords.bootloaderTitle, DownloadModeWords.bootloaderDetail) {
                HStack(spacing: 10) {
                    Button(DownloadModeWords.installMBootloader.uppercased()) { start(.mBootloader) }
                        .buttonStyle(.pixelProminent)
                    Button(DownloadModeWords.putBackMVave.uppercased()) { start(.mvaveBootloader) }
                        .buttonStyle(.pixel)
                }
            }
        }
    }

    private var chosenFirmware: StoredFirmware? {
        model.library.items.first { $0.id == firmwareID }
    }

    @ViewBuilder private var installControls: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(model.library.items) { firmware in
                    Button("\(firmware.name) \(firmware.version)") { firmwareID = firmware.id }
                }
            } label: {
                Text(
                    "\(chosenFirmware.map { "\($0.name) \($0.version)" } ?? DownloadModeWords.chooseFirmware) ▾"
                        .uppercased()
                )
                .font(.pixel(11, bold: true, relativeTo: .callout))
                .foregroundStyle(theme.bright)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(PixelBox(step: 2).strokeBorder(theme.dim, lineWidth: 2))
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            Button(DownloadModeWords.install.uppercased()) {
                if let chosenFirmware { start(.install(chosenFirmware, erasingSettings: erasesSettings)) }
            }
            .buttonStyle(.pixelProminent)
            .disabled(chosenFirmware == nil)
        }
        PixelToggle(DownloadModeWords.erasesSettings.uppercased(), isOn: $erasesSettings)
    }

    private func job(_ title: String, _ detail: String, @ViewBuilder controls: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("▸ \(title.uppercased())")
                .font(.pixel(11, bold: true, relativeTo: .callout))
                .foregroundStyle(theme.bright)
            NoteText(detail)
            controls()
        }
        .padding(.vertical, 4)
    }

    private func start(_ job: DownloadModeJob) {
        Task { await tools.start(job) }
    }
}

/// What a write will do, with what to know first, and the button to write it, in Retro.
struct RetroDownloadModeConfirm: View {
    @Environment(AppModel.self) private var model
    var plan: FlashPlanSummary
    var saved: SavedFlashBackup
    @State private var understands = false

    private var tools: DownloadModeController { model.downloadMode }

    /// Whether this puts m-bootloader on in place of M-VAVE's.
    private var isFirstMBootloader: Bool {
        tools.job == .mBootloader && !tools.hadMBootloader
    }

    var body: some View {
        PixelPanel(title: (tools.job?.title ?? DownloadModeWords.writeTitle).uppercased()) {
            MonoText("✓ \(DownloadModeWords.saved(saved))", size: 14)
            ForEach(plan.notes, id: \.self) { MonoText($0, size: 14) }
            NoteText(DownloadModeWords.changes(plan))
            ForEach(plan.warnings, id: \.self) { MonoText("! \($0)", size: 14) }
            MonoText(DownloadModeWords.recovery(plan), size: 14)
            if isFirstMBootloader {
                PixelPanel(title: "M-BOOTLOADER") {
                    MonoText(DownloadModeWords.mBootloaderChoiceTitle, size: 14)
                    ForEach(DownloadModeWords.mBootloaderChoice, id: \.self) { MonoText($0, size: 14) }
                    NoteText(DownloadModeWords.mBootloaderChoiceNote)
                }
            }
            PixelToggle(DownloadModeWords.keepsPluggedIn.uppercased(), isOn: $understands)
            HStack(spacing: 10) {
                // Keeping M-VAVE's is as easy to pick as installing m-bootloader.
                Button((isFirstMBootloader ? DownloadModeWords.keepMVave : "Cancel").uppercased()) {
                    Task { await tools.finish() }
                }
                .buttonStyle(.pixel)
                Button(
                    (isFirstMBootloader ? DownloadModeWords.installMBootloaderNow : DownloadModeWords.writeNow)
                        .uppercased()
                ) {
                    Task { await tools.confirm() }
                }
                .buttonStyle(.pixelProminent)
                .disabled(!understands)
            }
        }
    }
}
