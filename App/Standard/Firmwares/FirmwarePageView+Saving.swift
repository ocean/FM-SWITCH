import SwiftUI

/// Saving a firmware, the earlier releases saved here, and deleting them.
extension FirmwarePageView {
    /// Saves it here without installing, to install later, even offline.
    var saveButton: some View {
        Button("Save\(shownVersion) to this \(ThisDevice.name) for later") {
            Task { await save() }
        }
        .buttonStyle(.secondary)
        .disabled(isDownloading || entry.needsBuildChoice)
    }

    /// Earlier releases saved here, newest first, apart from the other release of a firmware that
    /// has a stable and a test one, which ``ReleaseChoice`` offers.
    var earlier: [StoredFirmware] {
        let otherRelease = entry.otherRelease == nil ? nil : library.stored(for: entry.choosingOtherRelease())
        return library.savedCopies(of: entry)
            .filter { copy in
                copy.id != stored?.id && copy.id != otherRelease?.id
                    && (entry.version.map { ReleaseVersion.isNewer($0, than: copy.version) } ?? true)
            }
            .sorted { ReleaseVersion.isNewer($0.version, than: $1.version) }
    }

    /// The saved copy installing uses: the earlier release picked, or this release when it's saved.
    var installable: StoredFirmware? { chosenEarlier ?? stored }

    /// The version installing gets, when there are versions to choose from, or nothing.
    var shownVersion: String {
        guard !earlier.isEmpty, let version = installable?.version ?? entry.version else { return "" }
        return " \(version)"
    }

    @ViewBuilder var installNote: some View {
        if let installable, !library.canRemove(installable) {
            Text("Comes with the app, so it installs even offline.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        } else if let installable {
            let note = Text("Saved, ready for offline install")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
            let delete = Button {
                library.remove(installable)
            } label: {
                Label("Delete this saved version", systemImage: "trash")
                    .lineLimit(1)
            }
            .buttonStyle(.danger)
            // Side by side where there's room, as on the Mac; otherwise the note goes above a
            // button the full width, so the label stays on one line.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    note.fixedSize()
                    Spacer(minLength: 0)
                    delete.fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    note
                    delete
                }
            }
        } else if !isConnected {
            Text("Downloads now. Plug in your FM-1 when you're ready to install.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
    }
}
