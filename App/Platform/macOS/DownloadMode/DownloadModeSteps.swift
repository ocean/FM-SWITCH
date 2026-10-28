import SwiftUI

/// Says whether the FM-1 is in download mode, and how to get it there.
struct DownloadModeConnectCard: View {
    @Environment(AppModel.self) private var model

    private var tools: DownloadModeController { model.downloadMode }

    var body: some View {
        DownloadModeCard {
            if tools.isInDownloadMode { inDownloadMode } else { howToEnter }
        }
    }

    @ViewBuilder private var inDownloadMode: some View {
        Label(DownloadModeWords.inDownloadMode, systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(Palette.goodInk)
        Text(DownloadModeWords.inDownloadModeDetail)
            .foregroundStyle(Palette.secondaryInk)
        if model.settings.transportKind == .simulated {
            Button(DownloadModeWords.leaveSimulated) { tools.leaveSimulatedDownloadMode() }
                .buttonStyle(.secondary)
        }
    }

    @ViewBuilder private var howToEnter: some View {
        Text(DownloadModeWords.enterTitle).font(.headline)
        if tools.canAskToEnter || model.settings.transportKind == .simulated {
            askToEnter
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(DownloadModeWords.enterWithMBootloader)
            Text(DownloadModeWords.enterWithMVave)
        }
        .foregroundStyle(Palette.secondaryInk)
        Text(DownloadModeWords.showsUpHere)
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        if let problem = tools.enteringProblem {
            Notice(problem, systemImage: "exclamationmark.triangle", isWarning: true)
        }
    }

    private var askToEnter: some View {
        HStack(spacing: 12) {
            Button {
                Task { await tools.enterDownloadMode() }
            } label: {
                if tools.isEntering {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(DownloadModeWords.askingToEnter)
                    }
                } else {
                    Text(DownloadModeWords.askToEnter)
                }
            }
            .buttonStyle(.prominent(Palette.accent))
            .disabled(tools.isEntering)
            Text(DownloadModeWords.askToEnterDetail)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
    }
}

/// The four jobs: back up, restore, install a firmware, and install a bootloader.
struct DownloadModeJobsCard: View {
    @Environment(AppModel.self) private var model
    /// Opens a file chooser for a backup from elsewhere, such as M-Flasher.
    var chooseFile: () -> Void
    @State private var backupID: SavedFlashBackup.ID?
    @State private var firmwareID: StoredFirmware.ID?
    @State private var erasesSettings = false

    private var tools: DownloadModeController { model.downloadMode }

    var body: some View {
        DownloadModeCard {
            Text(DownloadModeWords.jobsTitle).font(.headline)
            backUpJob
            Divider().overlay(Palette.line)
            job(DownloadModeWords.restoreTitle, DownloadModeWords.restoreDetail) {
                restoreControls
            }
            Divider().overlay(Palette.line)
            installJob
            Divider().overlay(Palette.line)
            bootloaderJob
        }
    }

    private var backUpJob: some View {
        job(DownloadModeWords.backUpTitle, DownloadModeWords.backUpDetail) {
            Button(DownloadModeWords.backUp) { start(.backUp) }
                .buttonStyle(.prominent(Palette.save))
        }
    }

    private var installJob: some View {
        job(DownloadModeWords.installTitle, DownloadModeWords.installDetail) {
            installControls
        }
    }

    private var bootloaderJob: some View {
        job(DownloadModeWords.bootloaderTitle, DownloadModeWords.bootloaderDetail) {
            HStack(spacing: 10) {
                Button(DownloadModeWords.installMBootloader) { start(.mBootloader) }
                    .buttonStyle(.prominent(Palette.accent))
                Button(DownloadModeWords.putBackMVave) { start(.mvaveBootloader) }
                    .buttonStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var restoreControls: some View {
        HStack(spacing: 10) {
            if !tools.backups.backups.isEmpty {
                Picker("Backup", selection: $backupID) {
                    Text(DownloadModeWords.chooseBackup).tag(SavedFlashBackup.ID?.none)
                    ForEach(tools.backups.backups) { backup in
                        Text(backup.date.formatted(date: .abbreviated, time: .shortened)).tag(Optional(backup.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                Button(DownloadModeWords.restore) {
                    if let backup = tools.backups.backups.first(where: { $0.id == backupID }) {
                        start(.restore(backup))
                    }
                }
                .buttonStyle(.prominent(Palette.accent))
                .disabled(backupID == nil)
            }
            Button(DownloadModeWords.chooseFile, action: chooseFile)
                .buttonStyle(.secondary)
        }
    }

    @ViewBuilder private var installControls: some View {
        HStack(spacing: 10) {
            Picker("Firmware", selection: $firmwareID) {
                Text(DownloadModeWords.chooseFirmware).tag(StoredFirmware.ID?.none)
                ForEach(model.library.items) { firmware in
                    Text("\(firmware.name) \(firmware.version)").tag(Optional(firmware.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            Button(DownloadModeWords.install) {
                if let firmware = model.library.items.first(where: { $0.id == firmwareID }) {
                    start(.install(firmware, erasingSettings: erasesSettings))
                }
            }
            .buttonStyle(.prominent(Palette.accent))
            .disabled(firmwareID == nil)
        }
        Toggle(DownloadModeWords.erasesSettings, isOn: $erasesSettings)
            .font(.callout)
    }

    private func job(_ title: String, _ detail: String, @ViewBuilder controls: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.bold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            controls()
        }
    }

    private func start(_ job: DownloadModeJob) {
        Task { await tools.start(job) }
    }
}

/// What a write will do, with what to know first, and the button to write it.
struct DownloadModeConfirmView: View {
    @Environment(AppModel.self) private var model
    var plan: FlashPlanSummary
    var saved: SavedFlashBackup
    @State private var understands = false

    private var tools: DownloadModeController { model.downloadMode }

    /// Whether this puts m-bootloader on in place of M-VAVE's, which changes what an iPhone can
    /// undo.
    private var isFirstMBootloader: Bool {
        tools.job == .mBootloader && !tools.hadMBootloader
    }

    /// What choosing m-bootloader means for switching firmware from an iPhone.
    private var mBootloaderChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DownloadModeWords.mBootloaderChoiceTitle)
                .font(.headline)
            ForEach(DownloadModeWords.mBootloaderChoice, id: \.self) { Text($0) }
            Text(DownloadModeWords.mBootloaderChoiceNote)
                .foregroundStyle(Palette.secondaryInk)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
    }

    var body: some View {
        DownloadModeCard {
            Text(tools.job?.title ?? DownloadModeWords.writeTitle).font(.title3.weight(.bold))
            Label(
                DownloadModeWords.saved(saved),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(Palette.goodInk)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.notes, id: \.self) { Text($0) }
                Text(DownloadModeWords.changes(plan))
                    .foregroundStyle(Palette.secondaryInk)
            }
            ForEach(plan.warnings, id: \.self) { warning in
                Notice(warning, systemImage: "exclamationmark.triangle", isWarning: true)
            }
            Notice(
                DownloadModeWords.recovery(plan),
                systemImage: "lifepreserver",
                isWarning: plan.writesBootArea || !plan.keepsMBootloader)
            if isFirstMBootloader { mBootloaderChoice }
            Toggle(DownloadModeWords.keepsPluggedIn, isOn: $understands)
            HStack(spacing: 10) {
                // Keeping M-VAVE's is as easy to pick as installing m-bootloader.
                Button(isFirstMBootloader ? DownloadModeWords.keepMVave : "Cancel") { Task { await tools.finish() } }
                    .buttonStyle(.secondary)
                Button(isFirstMBootloader ? DownloadModeWords.installMBootloaderNow : DownloadModeWords.writeNow) {
                    Task { await tools.confirm() }
                }
                .buttonStyle(.prominent(Palette.accent))
                .disabled(!understands)
            }
        }
    }
}
