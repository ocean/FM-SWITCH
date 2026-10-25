import SwiftUI
import UniformTypeIdentifiers

/// Backup & rescue: the Mac's download-mode tools.
///
/// It walks through allowing the helper and getting the FM-1 into download mode, then backs up,
/// restores, or installs a firmware or a bootloader, saving the whole flash before anything's
/// written.
struct DownloadModeView: View {
    @Environment(AppModel.self) private var model
    @State private var deleting: SavedFlashBackup?
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
                        "This is the simulated FM-1: nothing real is read or written.",
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
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [Self.backupType], onCompletion: importBackup)
        .confirmationDialog(
            "Delete this backup?", isPresented: isConfirmingDelete, titleVisibility: .visible, presenting: deleting
        ) { backup in
            Button("Delete", role: .destructive) {
                try? tools.backups.delete(backup)
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { backup in
            Text("The backup from \(backup.date.formatted(date: .abbreviated, time: .shortened)) goes for good.")
        }
    }

    /// A backup's `.bin` file, as FM1Kit and M-Flasher save it.
    private static let backupType = UTType(filenameExtension: "bin") ?? .data

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
            Text(
                """
                Download mode reads and writes the FM-1's whole flash: its bootloader, firmware, settings and \
                sounds. It works even when the firmware won't start.
                """
            )
            .foregroundStyle(Palette.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            if tools.needsHelper { DownloadModeHelperCard() }
            DownloadModeConnectCard()
            DownloadModeJobsCard(chooseFile: { isImporting = true })
                .disabled(!tools.isInDownloadMode || tools.needsHelper)
                .opacity(!tools.isInDownloadMode || tools.needsHelper ? 0.6 : 1)
            if let importProblem {
                Notice(importProblem, systemImage: "exclamationmark.triangle", isWarning: true)
            }
        }
    }

    /// Copies a chosen `.bin`, and its `.json` if it's beside it, in with the other backups, then
    /// restores it.
    private func importBackup(_ result: Result<URL, any Error>) {
        importProblem = nil
        do {
            let url = try result.get()
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            let saved = try tools.backups.save(FlashFiles(contentsOf: url))
            Task { await tools.start(.restore(saved)) }
        } catch {
            importProblem = error.localizedDescription
        }
    }

    // MARK: - Running.

    @ViewBuilder private func reading(_ fraction: Double) -> some View {
        progress(
            "Reading your FM-1",
            "It reads everything twice and checks both reads. Nothing is written.",
            fraction,
            colour: Palette.save)
    }

    @ViewBuilder private func writing(_ fraction: Double) -> some View {
        progress(
            "Writing to your FM-1",
            "Keep it plugged in and switched on until this finishes.",
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
            Label("Backed up", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.goodInk)
            Text("\(saved.contentsLine).")
            Text("It's saved as \(saved.file.lastPathComponent), which M-Flasher can restore too.")
                .foregroundStyle(Palette.secondaryInk)
            stillInDownloadMode
            doneButtons(showing: saved)
        }
    }

    private func nothingToWrite(_ saved: SavedFlashBackup) -> some View {
        DownloadModeCard {
            Label("Nothing to write", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.goodInk)
            Text("Your FM-1 already holds this, so nothing was written.")
            Text("Its flash is saved as \(saved.file.lastPathComponent).")
                .foregroundStyle(Palette.secondaryInk)
            stillInDownloadMode
            doneButtons(showing: saved)
        }
    }

    private func written(_ saved: SavedFlashBackup) -> some View {
        DownloadModeCard {
            Label("Written and checked", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.goodInk)
            Text("Every change matches the FM-1's own check. Switch it off and on to start it.")
            if tools.job == .mBootloader {
                Text(
                    """
                    From now on, holding PLAY while switching it on opens m-bootloader's menu, and holding REC \
                    starts download mode.
                    """
                )
                .foregroundStyle(Palette.secondaryInk)
            }
            Text("Its flash from before is saved as \(saved.file.lastPathComponent).")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
            doneButtons(showing: saved)
        }
    }

    private func failed(_ failure: FlashFailure, saved: SavedFlashBackup?) -> some View {
        DownloadModeCard {
            Label(
                failure.kind == .writeFailed ? "The write didn't finish" : "It stopped",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(Palette.warningInk)
            Text(failure.message)
            if failure.kind == .writeFailed, saved != nil {
                Text(
                    """
                    Keep your FM-1 plugged in and switched on: it's still in download mode. Put back the backup \
                    saved before writing, then try again.
                    """
                )
                .font(.callout.weight(.semibold))
                Button("Restore the backup") { Task { await tools.restoreAfterFailure() } }
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
        Text("Your FM-1 is still in download mode. Switch it off and on to start it.")
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
    }

    private func doneButtons(showing saved: SavedFlashBackup) -> some View {
        HStack(spacing: 10) {
            Button("Show in Finder") { SavedFiles.reveal(saved.file) }
                .buttonStyle(.secondary)
            Button("Done") { Task { await tools.finish() } }
                .buttonStyle(.prominent(Palette.accent))
        }
    }

    // MARK: - Saved backups.

    private var savedBackups: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Whole-flash backups")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(tools.backups.backups.enumerated()), id: \.element.id) { index, backup in
                    if index > 0 { Divider().overlay(Palette.line) }
                    FlashBackupRow(
                        backup: backup,
                        canRestore: tools.isInDownloadMode && !tools.needsHelper && tools.phase == .idle,
                        restore: { Task { await tools.start(.restore(backup)) } },
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

/// A whole-flash backup: when it was made, what's on it, and what can be done with it.
private struct FlashBackupRow: View {
    var backup: SavedFlashBackup
    var canRestore: Bool
    var restore: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(backup.contentsLine)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Menu {
                Button("Restore to my FM-1", systemImage: "arrow.counterclockwise", action: restore)
                    .disabled(!canRestore)
                Button("Show in Finder", systemImage: "folder") { SavedFiles.reveal(backup.file) }
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
