import SwiftUI

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
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.phosphor, model.settings.theme)
                .preferredColorScheme(colorScheme)
                .tint(model.settings.look == .retro ? model.settings.theme.bright : Palette.accent)
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
                #endif
        }
        #if os(macOS)
            // Opens wide enough for the sidebar layout.
            .defaultSize(width: 1180, height: 820)
        #endif

        #if os(macOS)
            // FM-SWITCH ▸ Settings… (⌘,), the Mac's home for settings, in the standard look.
            Settings {
                NavigationStack { StandardSettingsView() }
                    .environment(model)
                    .preferredColorScheme(model.settings.appearance.colorScheme)
                    .frame(width: 520, height: 620)
            }
        #endif
    }

    /// Retro is always dark; the standard look follows the Appearance setting.
    private var colorScheme: ColorScheme? {
        model.settings.look == .retro ? .dark : model.settings.appearance.colorScheme
    }
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
    let tipJar = TipJar()
    let device: DeviceController
    /// Whether firmwares and backups are in iCloud Drive, shared with the person's other devices,
    /// rather than only on this one.
    private(set) var isUsingICloud = false
    /// The folder firmwares and backups are kept in, each in a folder of their own.
    private(set) var filesFolder = SharedStorage.onDevice.root
    private var iCloudWatcher: ICloudWatcher?

    init() {
        device = DeviceController(library: library, history: history)
        device.configure(settings.transportKind, settings: settings)
        // Firmwares used to be kept, without names, where iOS can delete them for space. They're
        // kept in Firmwares now, so the old folder goes.
        try? FileManager.default.removeItem(at: AppDirectories.support.appending(path: "Firmware"))
        Task { await useICloudIfOn() }
    }

    /// Moves firmwares and backups into iCloud Drive, if it's on, and watches it for other devices'.
    private func useICloudIfOn() async {
        guard let folders = await SharedStorage.iCloudFolders() else { return }
        await library.move(to: folders.firmwares)
        await backups.move(to: folders.backups)
        isUsingICloud = true
        filesFolder = folders.root
        iCloudWatcher = ICloudWatcher { [weak self] in
            self?.library.reload()
            self?.backups.reload()
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
