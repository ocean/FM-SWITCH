import Foundation

/// Where firmwares and backups are kept.
///
/// When iCloud Drive is on, that's the app's own iCloud Drive folder, so the iPhone, iPad and Mac
/// apps see the same files; otherwise it's the app's Documents folder on this device. iCloud Drive
/// can list a file from another device before its contents have arrived, so a file is fetched
/// before it's read.
enum SharedStorage {
    static let containerIdentifier = "iCloud.dev.drewr.fmswitch"

    /// The folders on this device, used until iCloud Drive answers, or when it's off.
    static let onDevice = Folders(root: URL.documentsDirectory)

    /// Firmwares and backups, each in a folder of their own.
    struct Folders: Sendable {
        var root: URL

        var firmwares: URL { root.appending(path: "Firmwares", directoryHint: .isDirectory) }
        var backups: URL { root.appending(path: "Backups", directoryHint: .isDirectory) }
    }

    /// Where firmwares and backups are kept, for both looks' settings.
    @MainActor
    static func whereFilesAre(inICloud: Bool) -> String {
        inICloud
            ? "In the FM-SWITCH folder in iCloud Drive, so your other devices have them too."
            : "On this \(ThisDevice.name). Turn on iCloud Drive for FM-SWITCH to share them with your other devices."
    }

    enum Failure: LocalizedError {
        case notDownloaded

        var errorDescription: String? {
            "This file is still on its way from iCloud Drive. Check you're online, then try again."
        }
    }

    /// The app's iCloud Drive folders, or nil when iCloud Drive is off or the app can't use it.
    ///
    /// Finding them can take a while the first time, so it's done away from the main thread.
    static func iCloudFolders() async -> Folders? {
        await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier)
                .map { Folders(root: $0.appending(path: "Documents", directoryHint: .isDirectory)) }
        }.value
    }

    /// The files and folders in `folder`, including hidden ones.
    ///
    /// Any still on their way from iCloud Drive are listed by the names they'll have once they've
    /// arrived, and start downloading.
    static func contents(of folder: URL) -> [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return found.map { url in
            guard let arriving = arrivingName(of: url) else { return url }
            let real = url.deletingLastPathComponent().appending(path: arriving)
            try? FileManager.default.startDownloadingUbiquitousItem(at: real)
            return real
        }
    }

    /// Whether `url` is here, or on its way from iCloud Drive.
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
            || FileManager.default.fileExists(atPath: placeholder(for: url).path)
    }

    /// Waits for `url` to arrive from iCloud Drive, if it's still on its way.
    ///
    /// - Throws: ``Failure/notDownloaded`` if it hasn't arrived within `timeout`.
    static func download(_ url: URL, timeout: Duration = .seconds(60)) async throws {
        guard !isDownloaded(url) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = ContinuousClock.now + timeout
        while !isDownloaded(url) {
            guard ContinuousClock.now < deadline else { throw Failure.notDownloaded }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Moves everything in `source` into `destination`, joining folders that are in both.
    ///
    /// On a name that's in both, the copy already in `destination` is kept.
    /// Moving into iCloud Drive this way hands the files to it, so they upload.
    static func move(_ source: URL, into destination: URL) async {
        await Task.detached {
            moveNow(source, into: destination)
        }.value
    }

    private static func moveNow(_ source: URL, into destination: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path) else { return }
        try? manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let items = (try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for item in items {
            let target = destination.appending(path: item.lastPathComponent)
            let isFolder = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if manager.fileExists(atPath: target.path) {
                if isFolder { moveNow(item, into: target) } else { try? manager.removeItem(at: item) }
            } else {
                try? manager.setUbiquitous(true, itemAt: item, destinationURL: target)
            }
        }
        try? manager.removeItem(at: source)
    }

    /// Whether the contents of `url` are here, which they always are outside iCloud Drive.
    private static func isDownloaded(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard values?.isUbiquitousItem == true else { return true }
        return values?.ubiquitousItemDownloadingStatus == .current
    }

    /// iCloud Drive's stand-in for a file that hasn't arrived: `.name.icloud` beside where it'll be.
    private static func placeholder(for url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud")
    }

    /// The name a stand-in will have once its file has arrived, or nil if it isn't a stand-in.
    private static func arrivingName(of url: URL) -> String? {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }
}
