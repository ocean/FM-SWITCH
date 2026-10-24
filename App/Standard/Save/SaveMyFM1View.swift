import FM1Kit
import SwiftUI

/// Save my FM-1: keeps a copy of the projects and samples of an FM-1 running M-VAVE's open
/// firmware, and lists the copies kept so far.
struct SaveMyFM1View: View {
    /// Where the page is up to.
    private enum Stage: Equatable {
        case notConnected
        case waitingToFinish
        case otherFirmware(String)
        case ready
        case saving(Double)
        case saved(SavedBackup)
        case failed(String)
    }

    @Environment(AppModel.self) private var model
    @State private var deleting: SavedBackup?

    private var device: DeviceController { model.device }

    private var stage: Stage {
        switch device.backupRun {
        case .saving(let fraction): return .saving(fraction)
        case .succeeded(let backup): return .saved(backup)
        case .failed(let message): return .failed(message)
        case .idle: break
        }
        guard let identity = device.identity else { return .notConnected }
        if identity.isLoader { return .waitingToFinish }
        guard identity.isOpenFirmware else {
            if case .running(let name?) = DeviceSummary(model: model).state { return .otherFirmware(name) }
            return .otherFirmware(identity.text)
        }
        return .ready
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FM1Drawing(line1: screen.title, line2: screen.line, progress: screen.progress)
                    .padding(.top, 8)
                Group {
                    switch stage {
                    case .notConnected: notConnected
                    case .waitingToFinish: waitingToFinish
                    case .otherFirmware(let name): otherFirmware(name)
                    case .ready: ready
                    case .saving(let fraction): saving(fraction)
                    case .saved(let backup): saved(backup)
                    case .failed(let message): failed(message)
                    }
                }
                .transition(.opacity)
                if !model.backups.backups.isEmpty { earlierSaves }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .animation(Motion.fade, value: stage)
        }
        .background(Palette.ground)
        .navigationTitle("Save my FM-1")
        // Leaving mid-save would leave the FM-1 on another project.
        .navigationBarBackButtonHidden(device.backupRun.isRunning)
        .onAppear { model.backups.reload() }
        .onDisappear { device.dismissBackup() }
        .sensoryFeedback(trigger: device.backupRun) { _, run in
            switch run {
            case .succeeded: .success
            case .failed: .error
            default: nil
            }
        }
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

    /// What the drawing's screen says.
    private var screen: (title: String, line: String, progress: Double?) {
        switch stage {
        case .notConnected: ("SAVE", "Plug me in", nil)
        case .waitingToFinish: ("UPDATE", "Waiting…", nil)
        case .otherFirmware: ("SAVE", "Not this one", nil)
        case .ready: ("SAVE", "Ready", nil)
        case .saving(let fraction): ("SAVING", "\(Int(fraction * 100))%", fraction)
        case .saved: ("SAVED", "All done", nil)
        case .failed: ("SAVE", "Stopped", nil)
        }
    }

    // MARK: - Stages.

    private var notConnected: some View {
        Card {
            Text("Connect your FM-1").font(.headline)
            Text(
                """
                Switch it on and plug it into this \(ThisDevice.name) with a USB data cable. Saving works with \
                M-VAVE's open firmware.
                """
            )
            .foregroundStyle(Palette.secondaryInk)
        }
    }

    private var waitingToFinish: some View {
        Card {
            Text("Finish the install first").font(.headline)
            Text("Your FM-1 is waiting to finish an install. Carry on with it from My FM-1, then come back.")
                .foregroundStyle(Palette.secondaryInk)
        }
    }

    private func otherFirmware(_ name: String) -> some View {
        Card {
            Text("Only open firmware can be saved").font(.headline)
            Text(
                """
                Your FM-1 is running \(name). Saving works with M-VAVE's open firmware: other firmwares \
                have no known way to read their projects and samples.
                """
            )
            .foregroundStyle(Palette.secondaryInk)
        }
    }

    private var ready: some View {
        Card {
            Text("Keep a copy of your FM-1").font(.title3.weight(.bold))
            Text("This saves to your \(ThisDevice.name):").foregroundStyle(Palette.secondaryInk)
            VStack(alignment: .leading, spacing: 8) {
                SavedItem(text: "Every saved project")
                SavedItem(text: "The project you're working on, with any unsaved changes")
                SavedItem(text: "Your samples")
            }
            Text(
                """
                While it saves, your FM-1 opens each project in turn, then goes back to yours. Don't play \
                or change anything until it's done. Your saved projects and samples aren't changed.
                """
            )
            .font(.footnote)
            .foregroundStyle(Palette.warningInk)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.warningBackground))
            Button("Save my FM-1") {
                Task { await device.backUp(into: model.backups) }
            }
            .buttonStyle(.prominent(Palette.save))
        }
    }

    @ViewBuilder private func saving(_ fraction: Double) -> some View {
        VStack(spacing: 6) {
            Text("Saving your FM-1").font(.title.weight(.bold))
            Text("Don't play or change anything until it's done.")
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        ProgressBar(fraction: fraction, colour: Palette.save)
            .accessibilityLabel("Saving")
            .accessibilityValue("\(Int(fraction * 100)) percent")
        Text("Your \(ThisDevice.name) stays awake while this runs.")
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
    }

    private func saved(_ backup: SavedBackup) -> some View {
        Card {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.goodInk)
            Text("\(backup.contentsLine.prefix(1).uppercased())\(backup.contentsLine.dropFirst()).")
            Text(SavedFiles.whereBackupsAre(inICloud: model.isUsingICloud)).foregroundStyle(Palette.secondaryInk)
            Text("To put a project back, open its .fm1 file in M-VAVE's workbench.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
            HStack(spacing: 10) {
                ShareLink(item: BackupArchive(backup: backup), preview: SharePreview(backup.folder.lastPathComponent))
                    .buttonStyle(.secondary)
                if SavedFiles.canReveal {
                    Button("Show in Finder") { SavedFiles.reveal(backup.folder) }
                        .buttonStyle(.secondary)
                }
            }
            Button("Done") { device.dismissBackup() }
                .buttonStyle(.prominent(Palette.save))
        }
    }

    private func failed(_ message: String) -> some View {
        Card {
            Label("It stopped before finishing", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Palette.warningInk)
            Text(message)
            HStack(spacing: 10) {
                Button("Not now") { device.dismissBackup() }
                    .buttonStyle(.secondary)
                Button("Try again") {
                    device.dismissBackup()
                    Task { await device.backUp(into: model.backups) }
                }
                .buttonStyle(.prominent(Palette.save))
            }
        }
    }

    // MARK: - Earlier saves.

    private var earlierSaves: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Earlier saves")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(model.backups.backups.enumerated()), id: \.element.id) { index, backup in
                    if index > 0 { Divider().overlay(Palette.line) }
                    SavedBackupRow(backup: backup) { deleting = backup }
                }
            }
            .cardBackground()
        }
        .disabled(device.backupRun.isRunning)
    }
}

/// A white card holding a stage's words and buttons.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .foregroundStyle(Palette.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
    }
}

/// One thing a save keeps, ticked.
private struct SavedItem: View {
    var text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.save)
        }
    }
}

/// An earlier save: when it was made, what it holds, and a button to share it.
private struct SavedBackupRow: View {
    var backup: SavedBackup
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(backup.projectNames.isEmpty ? backup.contentsLine : backup.projectNames.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            shareButton
            moreMenu
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }

    private var shareButton: some View {
        ShareLink(item: BackupArchive(backup: backup), preview: SharePreview(backup.folder.lastPathComponent)) {
            icon("square.and.arrow.up")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accentText)
        .accessibilityLabel("Share")
    }

    private var moreMenu: some View {
        Menu {
            if SavedFiles.canReveal {
                Button("Show in Finder", systemImage: "folder") { SavedFiles.reveal(backup.folder) }
            }
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        } label: {
            icon("ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accentText)
        .accessibilityLabel("More")
    }

    /// A button's symbol, in a 44-point square so it's easy to hit.
    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .accessibilityHidden(true)
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
