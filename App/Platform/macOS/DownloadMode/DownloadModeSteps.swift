import SwiftUI

/// Asks the person to allow the privileged helper, which download mode needs.
struct DownloadModeHelperCard: View {
    @Environment(AppModel.self) private var model

    private var tools: DownloadModeController { model.downloadMode }

    var body: some View {
        DownloadModeCard {
            Text("Allow FM-SWITCH's helper").font(.headline)
            switch tools.helperStatus {
            case .needsApproval:
                Text(
                    """
                    Turn on FM-SWITCH in System Settings › General › Login Items & Extensions, under "Allow \
                    in the Background". This page carries on once it's on.
                    """
                )
                .foregroundStyle(Palette.secondaryInk)
                Button("Open System Settings") { tools.openLoginItems() }
                    .buttonStyle(.prominent(Palette.accent))
            case .missing:
                Text("The helper is missing from this copy of FM-SWITCH. Download the app again.")
                    .foregroundStyle(Palette.warningInk)
            case .notInstalled, .ready:
                Text(
                    """
                    Reading and writing the flash needs administrator rights, so FM-SWITCH has a small helper \
                    that macOS runs for it. You allow it once. It only runs while FM-SWITCH is using it, and \
                    only answers FM-SWITCH.
                    """
                )
                .foregroundStyle(Palette.secondaryInk)
                Button("Allow the helper…") { tools.installHelper() }
                    .buttonStyle(.prominent(Palette.accent))
            }
        }
    }
}

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
        Label("Your FM-1 is in download mode", systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(Palette.goodInk)
        Text("Nothing is written until you confirm it. Switch the FM-1 off and on to leave download mode.")
            .foregroundStyle(Palette.secondaryInk)
        if model.settings.transportKind == .simulated {
            Button("Switch the simulated FM-1 off and on") { tools.leaveSimulatedDownloadMode() }
                .buttonStyle(.secondary)
        }
    }

    @ViewBuilder private var howToEnter: some View {
        Text("Put your FM-1 in download mode").font(.headline)
        if tools.canAskToEnter || model.settings.transportKind == .simulated {
            askToEnter
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("With m-bootloader on it: switch it off, then hold REC while you switch it on.")
            Text(
                """
                With M-VAVE's bootloader, download mode is reached through V15 or Felucca, so plug it in \
                running one of those and use the button above.
                """
            )
        }
        .foregroundStyle(Palette.secondaryInk)
        Text("It shows up here once it's in download mode.")
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
                        Text("Restarting…")
                    }
                } else {
                    Text("Restart it in download mode")
                }
            }
            .buttonStyle(.prominent(Palette.accent))
            .disabled(tools.isEntering)
            Text("Works with V15 and Felucca. Nothing is written.")
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
            Text("What would you like to do?").font(.headline)
            backUpJob
            Divider().overlay(Palette.line)
            job("Restore a backup", "Puts a whole-flash backup back, writing only what's changed.") {
                restoreControls
            }
            Divider().overlay(Palette.line)
            installJob
            Divider().overlay(Palette.line)
            bootloaderJob
        }
    }

    private var backUpJob: some View {
        job(
            "Back up the whole FM-1",
            "Saves everything on it, in a file M-Flasher can restore too. Nothing is written."
        ) {
            Button("Back up") { start(.backUp) }
                .buttonStyle(.prominent(Palette.save))
        }
    }

    private var installJob: some View {
        job(
            "Install a firmware",
            """
            Writes a saved firmware straight to the flash, keeping the bootloader: for an FM-1 whose \
            firmware won't start. To swap firmware the usual way, use Firmwares.
            """
        ) {
            installControls
        }
    }

    private var bootloaderJob: some View {
        job(
            "Bootloader",
            """
            m-bootloader adds a recovery menu (hold PLAY) and download mode (hold REC), so a firmware \
            that won't start can always be fixed from a Mac. Installing V15 later puts M-VAVE's back.
            """
        ) {
            HStack(spacing: 10) {
                Button("Install m-bootloader 1.2") { start(.mBootloader) }
                    .buttonStyle(.prominent(Palette.accent))
                Button("Put back M-VAVE's") { start(.mvaveBootloader) }
                    .buttonStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var restoreControls: some View {
        HStack(spacing: 10) {
            if !tools.backups.backups.isEmpty {
                Picker("Backup", selection: $backupID) {
                    Text("Choose a backup").tag(SavedFlashBackup.ID?.none)
                    ForEach(tools.backups.backups) { backup in
                        Text(backup.date.formatted(date: .abbreviated, time: .shortened)).tag(Optional(backup.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                Button("Restore") {
                    if let backup = tools.backups.backups.first(where: { $0.id == backupID }) {
                        start(.restore(backup))
                    }
                }
                .buttonStyle(.prominent(Palette.accent))
                .disabled(backupID == nil)
            }
            Button("Choose a file…", action: chooseFile)
                .buttonStyle(.secondary)
        }
    }

    @ViewBuilder private var installControls: some View {
        HStack(spacing: 10) {
            Picker("Firmware", selection: $firmwareID) {
                Text("Choose a firmware").tag(StoredFirmware.ID?.none)
                ForEach(model.library.items) { firmware in
                    Text("\(firmware.name) \(firmware.version)").tag(Optional(firmware.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            Button("Install") {
                if let firmware = model.library.items.first(where: { $0.id == firmwareID }) {
                    start(.install(firmware, erasingSettings: erasesSettings))
                }
            }
            .buttonStyle(.prominent(Palette.accent))
            .disabled(firmwareID == nil)
        }
        Toggle("Erase the firmware's settings too", isOn: $erasesSettings)
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
            Text("m-bootloader: easier rescue, but less switching from your iPhone")
                .font(.headline)
            Text(
                """
                With m-bootloader, you can always rescue your FM-1 from this Mac by holding REC while \
                switching it on.
                """
            )
            Text(
                """
                But if you install AMB-1, Felucca or a firmware like them from your iPhone, getting back to \
                V15 or Open V12 will need this Mac.
                """
            )
            Text("If you mostly switch firmware on your iPhone, keeping M-VAVE's start-up is simpler.")
                .foregroundStyle(Palette.secondaryInk)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
    }

    var body: some View {
        DownloadModeCard {
            Text(tools.job?.title ?? "Write to your FM-1").font(.title3.weight(.bold))
            Label(
                "Your FM-1 as it is now is saved: \(saved.file.lastPathComponent).",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(Palette.goodInk)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.notes, id: \.self) { Text($0) }
                Text("It changes \(plan.sectorCount) of the flash's 256 parts of 4 KB.")
                    .foregroundStyle(Palette.secondaryInk)
            }
            ForEach(plan.warnings, id: \.self) { warning in
                Notice(warning, systemImage: "exclamationmark.triangle", isWarning: true)
            }
            Notice(recovery, systemImage: "lifepreserver", isWarning: plan.writesBootArea || !plan.keepsMBootloader)
            if isFirstMBootloader { mBootloaderChoice }
            Toggle("I'll keep my FM-1 plugged in and switched on until it's done", isOn: $understands)
            HStack(spacing: 10) {
                // Keeping M-VAVE's is as easy to pick as installing m-bootloader.
                Button(isFirstMBootloader ? "Keep M-VAVE's" : "Cancel") { Task { await tools.finish() } }
                    .buttonStyle(.secondary)
                Button(isFirstMBootloader ? "Install m-bootloader" : "Write to my FM-1") {
                    Task { await tools.confirm() }
                }
                .buttonStyle(.prominent(Palette.accent))
                .disabled(!understands)
            }
        }
    }

    /// What recovering would take if the write were cut off part-way.
    private var recovery: String {
        if plan.writesBootArea {
            """
            This writes the boot area, where the bootloader is. If the FM-1 is switched off or unplugged \
            while it's writing, it may not start, and recovering it could need a USB_KEY dongle.
            """
        } else if plan.keepsMBootloader {
            """
            The bootloader isn't touched, so if anything goes wrong, holding REC while switching it on \
            still reaches download mode, to put back the backup just saved.
            """
        } else {
            """
            The bootloader isn't touched, but with M-VAVE's bootloader download mode is only reached \
            through the firmware, so a firmware left unable to start could need a USB_KEY dongle to \
            recover. Installing m-bootloader first avoids that.
            """
        }
    }
}
