import AppKit

/// Where saved backups can be found: in the Finder.
enum SavedFiles {
    /// Whether the app can show a folder itself, as the Finder can.
    static let canReveal = true

    /// Where the Backups folder is.
    @MainActor
    static func whereBackupsAre(inICloud: Bool) -> String {
        inICloud
            ? "In iCloud Drive, in FM-SWITCH › Backups, on all your devices. Show in Finder opens it."
            : "In FM-SWITCH's Backups folder. Show in Finder opens it."
    }

    @MainActor
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// The app that ``open(_:)`` shows a folder in.
    static let folderAppName = "Finder"

    /// Opens `folder` in the Finder.
    @MainActor
    static func open(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
