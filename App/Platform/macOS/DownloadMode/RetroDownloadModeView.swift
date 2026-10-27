import SwiftUI

/// Retro's BACKUP & RESCUE: the Mac's download-mode tools, with the same steps as the standard
/// look's ``DownloadModeView``.
struct RetroDownloadModeView: View {
    @Environment(AppModel.self) private var model
    @State private var deleting: SavedFlashBackup?
    @State private var isImporting = false
    @State private var importProblem: String?

    private var tools: DownloadModeController { model.downloadMode }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: "BACKUP & RESCUE")
                if model.settings.transportKind == .simulated {
                    NoteText(DownloadModeWords.simulated)
                }
                Group {
                    switch tools.phase {
                    case .idle: steps
                    case .reading(let fraction):
                        progress(DownloadModeWords.readingTitle, DownloadModeWords.readingDetail, fraction)
                    case .confirming(let plan, let saved): RetroDownloadModeConfirm(plan: plan, saved: saved)
                    case .writing(let fraction, _):
                        progress(DownloadModeWords.writingTitle, DownloadModeWords.writingDetail, fraction)
                    case .backedUp(let saved): backedUp(saved)
                    case .nothingToWrite(let saved): nothingToWrite(saved)
                    case .written(let saved): written(saved)
                    case .failed(let failure, let saved): failed(failure, saved: saved)
                    }
                }
                if !tools.backups.backups.isEmpty { savedBackups }
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .scrollIndicators(.hidden)
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
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding {
            deleting != nil
        } set: { isPresented in
            if !isPresented { deleting = nil }
        }
    }

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

    // MARK: - Getting ready.

    @ViewBuilder private var steps: some View {
        MonoText(DownloadModeWords.intro, size: 14)
        if tools.needsHelper { RetroDownloadModeHelper() }
        RetroDownloadModeConnect()
        RetroDownloadModeJobs(chooseFile: { isImporting = true })
            .disabled(!tools.isInDownloadMode || tools.needsHelper)
            .opacity(!tools.isInDownloadMode || tools.needsHelper ? 0.5 : 1)
        if let importProblem {
            MonoText("! \(importProblem)", size: 14)
        }
    }

    private func progress(_ title: String, _ detail: String, _ fraction: Double) -> some View {
        PixelPanel(title: title.uppercased()) {
            MonoText(detail, size: 14)
            PixelProgressBar(fraction: fraction)
            MonoText("\(Int(fraction * 100))%", size: 14, dim: true)
        }
    }

    // MARK: - Finished.

    private func backedUp(_ saved: SavedFlashBackup) -> some View {
        PixelPanel(title: DownloadModeWords.backedUp.uppercased()) {
            MonoText("\(saved.contentsLine).", size: 14)
            NoteText(DownloadModeWords.savedAs(saved))
            NoteText(DownloadModeWords.stillInDownloadMode)
            doneButtons(showing: saved)
        }
    }

    private func nothingToWrite(_ saved: SavedFlashBackup) -> some View {
        PixelPanel(title: DownloadModeWords.nothingToWrite.uppercased()) {
            MonoText(DownloadModeWords.alreadyHoldsThis, size: 14)
            NoteText(DownloadModeWords.flashSavedAs(saved))
            NoteText(DownloadModeWords.stillInDownloadMode)
            doneButtons(showing: saved)
        }
    }

    private func written(_ saved: SavedFlashBackup) -> some View {
        PixelPanel(title: DownloadModeWords.written.uppercased()) {
            MonoText(DownloadModeWords.writtenDetail, size: 14)
            if tools.job == .mBootloader {
                NoteText(DownloadModeWords.mBootloaderKeys)
            }
            NoteText(DownloadModeWords.flashFromBefore(saved))
            doneButtons(showing: saved)
        }
    }

    private func failed(_ failure: FlashFailure, saved: SavedFlashBackup?) -> some View {
        let didntFinish = failure.kind == .writeFailed
        return PixelPanel(title: (didntFinish ? DownloadModeWords.writeFailed : DownloadModeWords.stopped).uppercased())
        {
            MonoText(failure.message, size: 14)
            if didntFinish, saved != nil {
                MonoText(DownloadModeWords.putBackBackup, size: 14)
                Button(DownloadModeWords.restoreBackup.uppercased()) {
                    Task { await tools.restoreAfterFailure() }
                }
                .buttonStyle(.pixelProminent)
            } else {
                HStack(spacing: 10) {
                    Button("CLOSE") { Task { await tools.finish() } }
                        .buttonStyle(.pixel)
                    if let job = tools.job {
                        Button("TRY AGAIN") { Task { await tools.start(job) } }
                            .buttonStyle(.pixelProminent)
                    }
                }
            }
        }
    }

    private func doneButtons(showing saved: SavedFlashBackup) -> some View {
        HStack(spacing: 10) {
            Button(DownloadModeWords.showInFinder.uppercased()) { SavedFiles.reveal(saved.file) }
                .buttonStyle(.pixel)
            Button("DONE") { Task { await tools.finish() } }
                .buttonStyle(.pixelProminent)
        }
    }

    // MARK: - Saved backups.

    private var savedBackups: some View {
        let canRestore = tools.isInDownloadMode && !tools.needsHelper && tools.phase == .idle
        return PixelPanel(title: DownloadModeWords.backupsTitle.uppercased()) {
            ForEach(tools.backups.backups) { backup in
                VStack(alignment: .leading, spacing: 6) {
                    MonoText(backup.date.formatted(date: .abbreviated, time: .shortened), size: 14)
                    NoteText(backup.contentsLine)
                    HStack(spacing: 8) {
                        Button(DownloadModeWords.restore.uppercased()) {
                            Task { await tools.start(.restore(backup)) }
                        }
                        .disabled(!canRestore)
                        Button("FINDER") { SavedFiles.reveal(backup.file) }
                        Button("DELETE") { deleting = backup }
                    }
                    .buttonStyle(.pixelCompact)
                }
                .padding(.vertical, 4)
            }
        }
        .disabled(tools.phase.isRunning)
    }
}
