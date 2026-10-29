import Foundation
import UserNotifications

#if os(iOS)
    import BackgroundTasks
#endif

/// Tells the person when a firmware they've saved has a newer release, with a notification.
///
/// On iPhone and iPad, iOS runs the check in the background about once a day, when it chooses; the
/// Mac checks once a day while the app's open. Each release is announced once, and tapping a
/// notification about one firmware opens its page.
@MainActor
final class FirmwareUpdateNotices: NSObject, UNUserNotificationCenterDelegate {
    /// The background check's ID, as Info.plist's `BGTaskSchedulerPermittedIdentifiers` lists it.
    static let taskID = "dev.drewr.fmswitch.firmware-updates"

    /// Opens a firmware's page, by catalogue ID, when its notification's tapped.
    var open: (String) -> Void = { _ in }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The newest release announced for each firmware, by catalogue ID.
    private var announced: [String: String] {
        get { defaults.dictionary(forKey: "announcedFirmwareUpdates") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "announcedFirmwareUpdates") }
    }

    /// Saved firmwares with a newer release that hasn't been announced yet.
    func unannounced(in entries: [CatalogueEntry], library: FirmwareLibrary) -> [CatalogueEntry] {
        let announced = announced
        return entries.filter { entry in
            library.outdated(for: entry) != nil && announced[entry.id] != entry.version ?? ""
        }
    }

    /// Counts these releases as announced, as when notifications are turned on: the cards already
    /// show the updates there are then.
    func markAnnounced(_ entries: [CatalogueEntry]) {
        var announced = announced
        for entry in entries { announced[entry.id] = entry.version ?? "" }
        self.announced = announced
    }

    /// Asks the person to allow notifications, if they haven't been asked.
    ///
    /// - Returns: Whether they're allowed.
    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Posts one notification about `entries`, then counts them as announced.
    func announce(_ entries: [CatalogueEntry]) async {
        guard !entries.isEmpty else { return }
        let request = UNNotificationRequest(
            identifier: "firmware-updates", content: Self.content(for: entries), trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            markAnnounced(entries)
        } catch {
            // Not counted, so the next check tries again.
        }
    }

    /// The notification's words: one firmware by name and version, several by name.
    static func content(for entries: [CatalogueEntry]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        if entries.count == 1, let entry = entries.first {
            content.title = [entry.name, entry.version, "is out"].compactMap(\.self).joined(separator: " ")
            content.body = "There's a newer release of a firmware you've saved. Tap to get it."
            content.userInfo = ["firmware": entry.id]
        } else {
            content.title = "\(entries.count) saved firmwares have updates"
            content.body = ListFormatter.localizedString(byJoining: entries.map(\.name)) + "."
        }
        return content
    }

    #if os(iOS)
        /// Asks iOS to run the check again in about a day; it decides when.
        static func scheduleCheck() {
            let request = BGAppRefreshTaskRequest(identifier: taskID)
            request.earliestBeginDate = .now.addingTimeInterval(20 * 60 * 60)
            try? BGTaskScheduler.shared.submit(request)
        }
    #endif

    // MARK: - UNUserNotificationCenterDelegate.

    /// Shows the notification even while the app's open.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Opens the firmware's page, for a notification about one.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let id = response.notification.request.content.userInfo["firmware"] as? String else { return }
        await MainActor.run { open(id) }
    }
}
