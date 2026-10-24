import Foundation

/// Watches the app's iCloud Drive folder, fetching whatever another device adds and saying when
/// something's changed.
///
/// Firmwares and backups are small, so every file is fetched as soon as it's listed: then they're
/// all here for installing offline.
@MainActor
final class ICloudWatcher {
    private let query = NSMetadataQuery()
    private var observers: [any NSObjectProtocol] = []

    /// Starts watching.
    ///
    /// - Parameter onChange: Called when files have been added, removed or have arrived.
    init(onChange: @escaping @MainActor () -> Void) {
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            let center = NotificationCenter.default
            let observer = center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.fetchEverything()
                    onChange()
                }
            }
            observers.append(observer)
        }
        query.start()
    }

    isolated deinit {
        query.stop()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func fetchEverything() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
                    != NSMetadataUbiquitousItemDownloadingStatusCurrent
            else { continue }
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }
}
