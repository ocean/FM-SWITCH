import SwiftUI

/// Save my FM-1 in Retro: keeps a copy of the projects and samples of an FM-1 running M-VAVE's
/// open firmware, and lists the copies kept so far.
struct RetroSaveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.phosphor) private var theme
    @State private var deleting: SavedBackup?

    private var device: DeviceController { model.device }
    private var isOpenFirmware: Bool { device.identity?.isOpenFirmware == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: "SAVE MY FM-1")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch device.backupRun {
                    case .idle: ready
                    case .saving(let fraction): progress(fraction)
                    case .succeeded(let backup): saved(backup)
                    case .failed(let reason): MonoText(reason, size: 15)
                    }
                    if !model.backups.backups.isEmpty { earlierSaves }
                }
            }
            .scrollIndicators(.hidden)
            buttons
        }
        .padding(20)
        .overlay { CRTOverlay() }
        // Leaving mid-save would leave the FM-1 on another project.
        .interactiveDismissDisabled(device.backupRun.isRunning)
        .onAppear { model.backups.reload() }
        .onDisappear { device.dismissBackup() }
        .confirmationDialog(
            "Delete this save?",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible,
            presenting: deleting
        ) { backup in
            Button("Delete", role: .destructive) {
                try? model.backups.delete(backup)
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { backup in
            Text("The copy from \(backup.date.formatted(date: .abbreviated, time: .shortened)) goes for good.")
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding {
            deleting != nil
        } set: { isPresented in
            if !isPresented { deleting = nil }
        }
    }

    @ViewBuilder private var ready: some View {
        if isOpenFirmware {
            MonoText(
                """
                Saves every saved project, the project you're working on (unsaved changes too) and your \
                samples to this \(ThisDevice.name).
                """,
                size: 14
            )
            NoteText(
                """
                While it saves, the FM-1 opens each project in turn, then goes back to yours. Don't play \
                or change anything until it's done. Your saved projects and samples aren't changed.
                """
            )
        } else {
            MonoText(
                """
                Saving works while the FM-1 runs M-VAVE's open firmware: other firmwares have no known \
                way to read their projects and samples.
                """,
                size: 14
            )
        }
    }

    private func progress(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MonoText("SAVING", size: 14)
                BlinkingCursor()
                Spacer()
                Text("\(Int(fraction * 100))%")
                    .font(.lcd(30))
                    .foregroundStyle(theme.bright)
            }
            PixelProgressBar(fraction: fraction)
            NoteText("Don't play or change anything until it's done.")
        }
    }

    @ViewBuilder private func saved(_ backup: SavedBackup) -> some View {
        MonoText("SAVED: \(backup.contentsLine).", size: 15)
        NoteText(SavedFiles.whereBackupsAre(inICloud: model.isUsingICloud))
        NoteText("To put a project back, open its .fm1 file in M-VAVE's workbench.")
    }

    private var earlierSaves: some View {
        PixelPanel(title: "EARLIER SAVES") {
            ForEach(model.backups.backups) { backup in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        MonoText(backup.date.formatted(date: .abbreviated, time: .shortened), size: 15)
                        NoteText(
                            backup.projectNames.isEmpty
                                ? backup.contentsLine : backup.projectNames.joined(separator: ", "))
                    }
                    Spacer(minLength: 0)
                    ShareLink(
                        item: BackupArchive(backup: backup), preview: SharePreview(backup.folder.lastPathComponent)
                    ) {
                        Text("SHARE")
                    }
                    .buttonStyle(.pixelCompact)
                    Button("DELETE") { deleting = backup }
                        .buttonStyle(.pixelCompact)
                }
            }
        }
        .disabled(device.backupRun.isRunning)
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 10) {
            switch device.backupRun {
            case .idle:
                Button("CLOSE") { dismiss() }
                    .buttonStyle(.pixel)
                if isOpenFirmware {
                    Button("SAVE") { Task { await device.backUp(into: model.backups) } }
                        .buttonStyle(.pixelProminent)
                        .disabled(device.isWriting)
                }
            case .saving:
                EmptyView()
            case .succeeded:
                Button("CLOSE") { dismiss() }
                    .buttonStyle(.pixelProminent)
            case .failed:
                Button("CLOSE") { dismiss() }
                    .buttonStyle(.pixel)
                Button("TRY AGAIN") {
                    device.dismissBackup()
                    Task { await device.backUp(into: model.backups) }
                }
                .buttonStyle(.pixelProminent)
                .disabled(device.isWriting)
            }
        }
    }
}

extension View {
    /// Presents ``RetroSaveView`` while `isPresented` is set.
    func retroSaveSheet(isPresented: Binding<Bool>, model: AppModel, theme: PhosphorTheme) -> some View {
        sheet(isPresented: isPresented) {
            RetroSaveView()
                .environment(model)
                .environment(\.phosphor, theme)
                .pixelSheetSize()
                .presentationBackground(theme.background)
        }
    }
}
