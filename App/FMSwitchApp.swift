import SwiftUI
import UserNotifications

@main
struct FMSwitchApp: App {
    @State private var model = AppModel()
    #if os(iOS)
        @State private var isLaunching = true
    #endif

    init() {
        // The model isn't usable from here yet, so this reads the saved look itself.
        SystemAppearance.apply(for: AppSettings.savedLook())
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindow) {
            RootView()
                .environment(model)
                .environment(\.phosphor, model.settings.theme)
                .windowAppearance(colorScheme)
                .tint(model.settings.look == .retro ? model.settings.theme.bright : Palette.accent)
                .opensLinksInApp()
                .onChange(of: model.settings.look) { _, look in SystemAppearance.apply(for: look) }
                #if os(iOS)
                    .overlay {
                        if isLaunching { LaunchHandOff { isLaunching = false } }
                    }
                #endif
                #if DEBUG && os(macOS)
                    .onAppear { DebugSnapshot.scheduleIfAsked() }
                #endif
                #if os(macOS)
                    .frame(minWidth: 420, minHeight: 560)
                    .task { await model.updates.keepChecking() }
                    .task { await model.keepCheckingForFirmwareUpdates() }
                #endif
        }
        #if os(iOS)
            .backgroundTask(.appRefresh(FirmwareUpdateNotices.taskID)) {
                await model.checkForFirmwareUpdatesInBackground()
            }
        #endif
        #if os(macOS)
            // Opens wide enough for the sidebar layout.
            .defaultSize(width: 1180, height: 820)
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") { Task { await model.updates.checkAndReport() } }
                }
                // Settings are a page in the window, in both looks, rather than a window of their own.
                CommandGroup(replacing: .appSettings) {
                    SettingsCommand(model: model)
                }
            }
        #endif
    }

    static let mainWindow = "main"

    /// Retro is always dark; the standard look follows the Appearance setting.
    private var colorScheme: ColorScheme? {
        model.settings.look == .retro ? .dark : model.settings.appearance.colorScheme
    }
}

/// A page asked for from outside the look's own navigation.
enum RequestedPage: Equatable {
    case help(HelpTopic)
    /// A firmware's page, by catalogue ID.
    case firmware(String)
    /// From FM-SWITCH ▸ Settings… on the Mac.
    case settings
}

/// Everything the screens share.
@MainActor
@Observable
final class AppModel {
    let settings = AppSettings()
    let catalogue = CatalogueStore()
    let library = FirmwareLibrary()
    let history = FlashHistory()
    let backups = BackupStore()
    let starred = StarredFirmwares()
    let tipJar = TipJar()
    /// Tells the person when firmwares they've saved have newer releases, once they've asked.
    let updateNotices = FirmwareUpdateNotices()
    let device: DeviceController
    #if os(macOS)
        /// Whole-flash backups, restores and installs in the chip's download mode.
        let downloadMode: DownloadModeController
        /// Whether a newer FM-SWITCH is out on GitHub.
        let updates = UpdateChecker()
    #endif
    /// A page a warning, an error or the menu bar asked to open, until the look's frame opens it.
    var requestedPage: RequestedPage?
    /// Whether firmwares and backups are in iCloud Drive, shared with the person's other devices,
    /// rather than only on this one.
    private(set) var isUsingICloud = false
    /// The folder firmwares and backups are kept in, each in a folder of their own.
    private(set) var filesFolder = SharedStorage.onDevice.root
    private var iCloudWatcher: ICloudWatcher?

    init() {
        device = DeviceController(library: library, history: history)
        device.configure(settings.transportKind, settings: settings)
        #if os(macOS)
            downloadMode = DownloadModeController(
                library: library,
                device: device,
                backupsFolder: { [backups] in backups.directory },
                isSimulated: { [settings] in settings.transportKind == .simulated })
        #endif
        // Firmwares used to be kept, without names, where iOS can delete them for space. They're
        // kept in Firmwares now, so the old folder goes.
        try? FileManager.default.removeItem(at: AppDirectories.support.appending(path: "Firmware"))
        Task { await useICloudIfOn() }
        UNUserNotificationCenter.current().delegate = updateNotices
        updateNotices.open = { [weak self] id in self?.requestedPage = .firmware(id) }
    }

    // MARK: - Firmware update notifications.

    /// Whether turning update notifications on found notifications aren't allowed for the app.
    private(set) var areNotificationsRefused = false

    /// The Settings switch for update notifications.
    var notifiesFirmwareUpdatesBinding: Binding<Bool> {
        Binding {
            self.settings.notifiesFirmwareUpdates
        } set: { isOn in
            Task { await self.setNotifiesFirmwareUpdates(isOn) }
        }
    }

    /// Turns update notifications on, once the person allows notifications, or off.
    ///
    /// Updates there are already aren't announced, as the cards show them.
    ///
    /// - Returns: False when notifications aren't allowed, so they stay off.
    @discardableResult
    func setNotifiesFirmwareUpdates(_ isOn: Bool) async -> Bool {
        settings.hasOfferedUpdateNotices = true
        guard isOn else {
            settings.notifiesFirmwareUpdates = false
            return true
        }
        guard await updateNotices.requestPermission() else {
            settings.notifiesFirmwareUpdates = false
            areNotificationsRefused = true
            return false
        }
        areNotificationsRefused = false
        updateNotices.markAnnounced(updateNotices.unannounced(in: catalogue.entries, library: library))
        settings.notifiesFirmwareUpdates = true
        #if os(iOS)
            FirmwareUpdateNotices.scheduleCheck()
        #endif
        return true
    }

    /// Refreshes the firmware list and announces new releases of saved firmwares, when that's on.
    func checkForFirmwareUpdates() async {
        guard settings.notifiesFirmwareUpdates else { return }
        await catalogue.refresh()
        library.reload()
        await updateNotices.announce(updateNotices.unannounced(in: catalogue.entries, library: library))
    }

    #if os(iOS)
        /// The background check iOS runs about once a day, which asks for the next one first.
        func checkForFirmwareUpdatesInBackground() async {
            if settings.notifiesFirmwareUpdates { FirmwareUpdateNotices.scheduleCheck() }
            await checkForFirmwareUpdates()
        }
    #else
        /// Checks once the launch refresh is done, then once a day while the app's open.
        func keepCheckingForFirmwareUpdates() async {
            var wait = Duration.seconds(60)
            while (try? await Task.sleep(for: wait)) != nil {
                await checkForFirmwareUpdates()
                wait = .seconds(24 * 60 * 60)
            }
        }
    #endif

    /// Moves firmwares, backups and stars into iCloud Drive, if it's on, and watches it for other devices'.
    private func useICloudIfOn() async {
        guard let folders = await SharedStorage.iCloudFolders() else { return }
        await library.move(to: folders.firmwares)
        await backups.move(to: folders.backups)
        await starred.move(to: folders.root)
        isUsingICloud = true
        filesFolder = folders.root
        iCloudWatcher = ICloudWatcher { [weak self] in
            self?.library.reload()
            self?.backups.reload()
            self?.starred.reload()
            #if os(macOS)
                self?.downloadMode.backups.reload()
            #endif
        }
    }

    /// Whether to offer Save my FM-1: it only works on M-VAVE's open firmware, so it's offered
    /// while the FM-1 is running it, or while there are earlier saves to look at.
    var offersSaveMyFM1: Bool {
        device.identity?.isOpenFirmware == true || device.backupRun != .idle || !backups.backups.isEmpty
    }

    func applyConnectionSettings() {
        device.configure(settings.transportKind, settings: settings)
    }

    /// The tip card to slide up, if one's due.
    ///
    /// Debug builds take `-tipNudgeInstalls 5` as a launch argument to count that many installs,
    /// for UI tests and screenshots.
    var tipNudge: TipNudge? {
        TipNudge.due(installs: installCount, shown: settings.tipNudgesShown)
    }

    func dismissTipNudge() {
        settings.tipNudgesShown = TipNudge.reached(installs: installCount).count
    }

    private var installCount: Int {
        #if DEBUG
            if let installs = UserDefaults.standard.object(forKey: "tipNudgeInstalls") as? String {
                return Int(installs) ?? 0
            }
        #endif
        return history.records.count
    }

    /// Starts MIDI again if it couldn't start before. iOS can start the app before it's opened (or
    /// straight after Xcode installs it), and CoreMIDI may refuse it then.
    func retryConnectionIfUnavailable() {
        guard device.transportError != nil else { return }
        applyConnectionSettings()
    }
}
