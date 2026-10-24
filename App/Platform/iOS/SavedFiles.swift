import UIKit

/// Where saved backups can be found: the Files app.
enum SavedFiles {
    /// Whether the app can show a folder itself; on iPhone and iPad it's the Files app's job.
    static let canReveal = false

    /// Where the Backups folder is, in the words the Files app uses.
    @MainActor
    static func whereBackupsAre(inICloud: Bool) -> String {
        inICloud
            ? "In the Files app, under iCloud Drive › FM-SWITCH › Backups, on all your devices."
            : "In the Files app, under On My \(UIDevice.current.model) › FM-SWITCH › Backups."
    }

    static func reveal(_: URL) {}

    /// The app that ``open(_:)`` shows a folder in.
    static let folderAppName = "Files"

    /// Opens `folder` in the Files app.
    @MainActor
    static func open(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The Files app opens any folder it can reach given its path this way.
        guard let url = URL(string: "shareddocuments://" + folder.path(percentEncoded: true)) else { return }
        UIApplication.shared.open(url)
    }
}
