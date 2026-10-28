import SwiftUI

/// Backup & rescue: the Mac's download-mode tools.
///
/// It walks through getting the FM-1 into download mode, then backs up,
/// restores, or installs a firmware or a bootloader, saving the whole flash before anything's
/// written.
struct DownloadModeView: View {
    @Environment(AppModel.self) private var model
    @State private var deleting: SavedFlashBackup?
    @State private var renaming: SavedFlashBackup?
    @State private var isImporting = false
    @State private var importProblem: String?

    private var tools: DownloadModeController { model.downloadMode }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FM1Drawing(line1: screen.title, line2: screen.line, litKey: screen.key, progress: screen.progress)
                    .padding(.top, 8)
                if model.settings.transportKind == .simulated {
                    Notice(
                        DownloadModeWords.simulated,
                        systemImage: "info.circle",
                        isWarning: false)
                }
                Group {
                    switch tools.phase {
                    case .idle: steps
                    case .reading(let fraction): reading(fraction)
                    case .confirming(let plan, let saved): DownloadModeConfirmView(plan: plan, saved: saved)
                    case .writing(let fraction, _): writing(fraction)
                    case .backedUp(let saved): backedUp(saved)
                    case .nothingToWrite(let saved): nothingToWrite(saved)
                    case .written(let saved): written(saved)
                    case .failed(let failure, let saved): failed(failure, saved: saved)
                    }
                }
                .transition(.opacity)
                if !tools.backups.backups.isEmpty { savedBackups }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .animation(Motion.fade, value: tools.phase)
        }
        .background(Palette.ground)
        .navigationTitle("Backup & rescue")
        .task { await tools.watch() }
        .onAppear { tools.backups.reload() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [DownloadModeController.backupType],
            onCompletion: importBackup
        )
        .confirmationDialog(
            DownloadModeWords.deleteTitle,
            isPresented: isConfirmingDelete,
            titleVisibility: .visible,
            presenting: deleting
        ) { backup in
            Button("Delete", role: .destructive) {
                try? tools.backups.delete(backup)
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { backup in
            Text(DownloadModeWords.deleteDetail(backup))
        }
        .renamingBackup($renaming, in: tools.backups)
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding {
            deleting != nil
        } set: { isPresented in
            if !isPresented { deleting = nil }
        }
    }

    /// What the drawing's screen says, and the key it lights.
    private struct ScreenText {
        var title: String
        var line = ""
        var key: FM1Drawing.Key?
        var progress: Double?
    }

    private var screen: ScreenText {
        switch tools.phase {
        case .idle where tools.isInDownloadMode: ScreenText(title: "DOWNLOAD", line: "Mode")
        case .idle: ScreenText(title: "RESCUE", line: "Hold REC", key: .rec)
        case .reading(let fraction): ScreenText(title: "READING", line: "\(Int(fraction * 100))%", progress: fraction)
        case .confirming: ScreenText(title: "READY", line: "To write")
        case .writing(let fraction, _):
            ScreenText(title: "WRITING", line: "\(Int(fraction * 100))%", progress: fraction)
        case .backedUp, .nothingToWrite: ScreenText(title: "SAVED", line: "All done")
        case .written: ScreenText(title: "DONE", line: "Verified")
        case .failed: ScreenText(title: "STOPPED")
        }
    }

    // MARK: - Getting ready.

    private var steps: some View {
        VStack(spacing: 14) {
            Text(DownloadModeWords.intro)
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(DownloadModeWords.password)
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            DownloadModeConnectCard()
            DownloadModeJobsCard(chooseFile: { isImporting = true })
                .disabled(!tools.isInDownloadMode)
                .opacity(tools.isInDownloadMode ? 1 : 0.6)
            if let importProblem {
                Notice(importProblem, systemImage: "exclamationmark.triangle", isWarning: true)
            }
        }
    }

    /// Restores a chosen `.bin`.
    private func importBackup(_ result: Result<URL, any Error>) {
        importProblem = nil
        Task {
            do {
                try await tools.restoreImported(result.get())
            } catch {
                importProblem = error.localizedDescription
            }
        }
    }

    // MARK: - Running.

    @ViewBuilder private func reading(_ fraction: Double) -> some View {
        progress(
            DownloadModeWords.readingTitle,
            DownloadModeWords.readingDetail,
            fraction,
            colour: Palette.save)
    }

    @ViewBuilder private func writing(_ fraction: Double) -> some View {
        progress(
            DownloadModeWords.writingTitle,
            DownloadModeWords.writingDetail,
            fraction,
            colour: Palette.accent)
    }

    @ViewBuilder private func progress(_ title: String, _ detail: String, _ fraction: Double, colour: Color)
        -> some View
    {
        VStack(spacing: 6) {
            Text(title).font(.title.weight(.bold))
            Text(detail)
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        ProgressBar(fraction: fraction, colour: colour)
            .accessibilityLabel(title)
            .accessibilityValue("\(Int(fraction * 100)) percent")
    }

    // MARK: - Finished.

    private func backedUp(_ saved: SavedFlashBackup) -> some View {
        DownloadModeCard {
            Label(DownloadModeWords.backedUp, systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.goodInk)
            Text("\(saved.contentsLine).")
            Text(DownloadModeWords.savedAs(saved))
                .foregroundStyle(Palette.secondaryInk)
            stillInDownloadMode
            doneButtons(showing: saved)
        }
    }

    private func nothingToWrite(_ saved: SavedFlashBackup) -> some View {
        DownloadModeCard {
            Label(DownloadModeWords.nothingToWrite, systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.goodInk)
            Text(DownloadModeWords.alreadyHoldsThis)
            Text(DownloadModeWords.flashSavedAs(saved))
                .foregroundStyle(Palette.secondaryInk)
            stillInDownloadMode
            doneButtons(showing: saved)
        }
    }

    private func written(_ saved: SavedFlashBackup) -> some View {
        DownloadModeCard {
            Label(DownloadModeWords.written, systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.goodInk)
            Text(DownloadModeWords.writtenDetail)
            if tools.job == .mBootloader {
                Text(DownloadModeWords.mBootloaderKeys)
                    .foregroundStyle(Palette.secondaryInk)
            }
            Text(DownloadModeWords.flashFromBefore(saved))
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
            doneButtons(showing: saved)
        }
    }

    private func failed(_ failure: FlashFailure, saved: SavedFlashBackup?) -> some View {
        DownloadModeCard {
            Label(
                failure.kind == .writeFailed ? DownloadModeWords.writeFailed : DownloadModeWords.stopped,
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(Palette.warningInk)
            Text(failure.message)
            if failure.kind == .writeFailed, saved != nil {
                Text(DownloadModeWords.putBackBackup)
                    .font(.callout.weight(.semibold))
                Button(DownloadModeWords.restoreBackup) { Task { await tools.restoreAfterFailure() } }
                    .buttonStyle(.prominent(Palette.accent))
            } else {
                HStack(spacing: 10) {
                    Button("Close") { Task { await tools.finish() } }
                        .buttonStyle(.secondary)
                    if let job = tools.job {
                        Button("Try again") { Task { await tools.start(job) } }
                            .buttonStyle(.prominent(Palette.accent))
                    }
                }
            }
        }
    }

    private var stillInDownloadMode: some View {
        Text(DownloadModeWords.stillInDownloadMode)
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
    }

    private func doneButtons(showing saved: SavedFlashBackup) -> some View {
        HStack(spacing: 10) {
            Button(DownloadModeWords.showInFinder) { SavedFiles.reveal(saved.file) }
                .buttonStyle(.secondary)
            Button("Done") { Task { await tools.finish() } }
                .buttonStyle(.prominent(Palette.accent))
        }
    }

    // MARK: - Saved backups.

    private var savedBackups: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DownloadModeWords.backupsTitle)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(tools.backups.backups.enumerated()), id: \.element.id) { index, backup in
                    if index > 0 { Divider().overlay(Palette.line) }
                    FlashBackupRow(
                        backup: backup,
                        canRestore: tools.isInDownloadMode && tools.phase == .idle,
                        restore: { Task { await tools.start(.restore(backup)) } },
                        rename: { renaming = backup },
                        delete: { deleting = backup })
                }
            }
            .cardBackground()
        }
        .disabled(tools.phase.isRunning)
    }
}

/// A white card holding a step's words and buttons.
struct DownloadModeCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .foregroundStyle(Palette.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
    }
}

/// A whole-flash backup: its name or when it was made, what's on it, and what can be done with it.
private struct FlashBackupRow: View {
    var backup: SavedFlashBackup
    var canRestore: Bool
    var restore: () -> Void
    var rename: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(backup.title)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(backup.detailLine)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Menu {
                Button(DownloadModeWords.restoreToFM1, systemImage: "arrow.counterclockwise", action: restore)
                    .disabled(!canRestore)
                Button(DownloadModeWords.showInFinder, systemImage: "folder") { SavedFiles.reveal(backup.file) }
                Button("\(DownloadModeWords.rename)…", systemImage: "pencil", action: rename)
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityHidden(true)
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accentText)
            .accessibilityLabel("More")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }
}
