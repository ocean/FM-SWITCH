import SwiftUI

/// The standard look's frame: a stack of pages on iPhone, and a sidebar on the Mac and iPad.
///
/// The install covers everything until it ends.
struct StandardRootView: View {
    /// The sidebar's sections.
    enum Section: Hashable {
        case myFM1
        case firmwares
        /// Saved and starred firmwares.
        case mine
        case save
        /// The Mac's download-mode tools.
        case downloadMode
        case help
        case settings
    }

    /// The pages the iPhone's stack can show.
    enum Page: Hashable {
        case firmwares
        case mine
        case firmware(CatalogueEntry)
        case save
        /// Help, open at a topic or at none.
        case help(HelpTopic?)
        case settings
    }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var section: Section? = .myFM1
    @State private var path: [Page] = []
    @State private var selectedFirmwareID: String?
    /// The topic Help opens at in the sidebar layout, when a warning or an error asked for one.
    @State private var helpTopic: HelpTopic?

    private var usesSidebar: Bool {
        #if os(macOS)
            true
        #else
            sizeClass == .regular
        #endif
    }

    private var isInstalling: Bool { model.device.job != nil }

    /// Whether the FM-1's flash is being read or written in download mode.
    private var isUsingDownloadMode: Bool {
        #if os(macOS)
            model.downloadMode.phase.isRunning
        #else
            false
        #endif
    }

    private var tipNudge: TipNudge? {
        isInstalling || model.settings.needsSafetyNotice ? nil : model.tipNudge
    }

    var body: some View {
        Group {
            if usesSidebar { sidebarLayout } else { stackLayout }
        }
        .tint(Palette.accentText)
        .disabled(isInstalling || model.settings.needsSafetyNotice)
        .accessibilityHidden(isInstalling || model.settings.needsSafetyNotice)
        .overlay {
            if isInstalling {
                InstallingView()
                    .transition(reducesMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .animation(Motion.standard(reducingMotion: reducesMotion), value: isInstalling)
        // Initially too, for Settings… chosen while the window was closed, which opens a new one.
        .onChange(of: model.requestedPage, initial: true) { _, page in
            guard let page else { return }
            open(page)
            model.requestedPage = nil
        }
        .overlay(alignment: .bottom) {
            if let nudge = tipNudge {
                TipNudgeCard(nudge: nudge)
                    .transition(reducesMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        // After an install, it waits for the install screen to go first.
        .animation(Motion.standard(reducingMotion: reducesMotion).delay(0.6), value: tipNudge)
        .overlay {
            if model.settings.needsSafetyNotice {
                WelcomeNoticeView()
                    .transition(.opacity)
            }
        }
    }

    private func open(_ page: RequestedPage) {
        switch page {
        case .help(let topic) where usesSidebar:
            helpTopic = topic
            section = .help
        case .help(let topic):
            path.append(.help(topic))
        case .settings where usesSidebar:
            section = .settings
        case .settings:
            path = [.settings]
        }
    }

    // MARK: - iPhone.

    private var stackLayout: some View {
        NavigationStack(path: $path) {
            HomeView(
                openFirmwares: { path.append(.firmwares) },
                openMine: { path.append(.mine) },
                openSave: { path.append(.save) },
                openSettings: { path.append(.settings) },
                openHelp: { path.append(.help(nil)) }
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: Page.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            #if DEBUG
                .task { await openPageFromLaunchArguments() }
            #endif
            .navigationDestination(for: Page.self, destination: destination)
        }
    }

    @ViewBuilder private func destination(_ page: Page) -> some View {
        switch page {
        case .firmwares:
            FirmwareListView { path.append(.firmware($0)) }
        case .mine:
            MyFirmwaresView { path.append(.firmware($0)) }
        case .firmware(let entry):
            FirmwarePageView(listed: entry)
        case .save:
            SaveMyFM1View()
        case .help(let topic):
            HelpView(opening: topic)
        case .settings:
            StandardSettingsView()
        }
    }

    // MARK: - Mac and iPad.

    private var sidebarLayout: some View {
        NavigationSplitView {
            sidebar
                #if DEBUG
                    .task { openSectionFromLaunchArguments() }
                #endif
        } detail: {
            NavigationStack {
                switch section ?? .myFM1 {
                case .myFM1:
                    HomeView(
                        openFirmwares: { section = .firmwares },
                        openSave: { section = .save },
                        openSettings: { section = .settings })
                case .firmwares:
                    sideBySide {
                        FirmwareListView(selectedID: selectedFirmwareID) { select($0) }
                    }
                case .mine:
                    sideBySide {
                        MyFirmwaresView(selectedID: selectedFirmwareID) { select($0) }
                    }
                case .save:
                    SaveMyFM1View()
                case .downloadMode:
                    #if os(macOS)
                        DownloadModeView()
                    #endif
                case .help:
                    HelpView(opening: helpTopic, openBackupAndRescue: { section = .downloadMode })
                        .id(helpTopic)
                case .settings:
                    StandardSettingsView()
                }
            }
        }
        // Help opens at the asked-for topic once; chosen from the sidebar later, it opens at none.
        .onChange(of: section) { _, section in
            if section != .help { helpTopic = nil }
        }
    }

    /// The sidebar's sections.
    private var sidebar: some View {
        List(selection: $section) {
            SwiftUI.Section("Device") {
                Label {
                    Text("My FM-1")
                } icon: {
                    Image(systemName: "pianokeys").imageScale(.large)
                }
                .tag(Section.myFM1)
                .listItemTint(.monochrome)
            }
            tasks
            SwiftUI.Section {
                Label("Help", systemImage: "lifepreserver")
                    .tag(Section.help)
                    .listItemTint(Palette.good)
            }
            SwiftUI.Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(Section.settings)
                    .listItemTint(.monochrome)
            }
        }
        // Leaving mid-save would leave the FM-1 on another project, and leaving mid-write would
        // hide how it's going.
        .disabled(model.device.backupRun.isRunning || isUsingDownloadMode)
        .navigationTitle("FM-SWITCH")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }

    /// The sidebar's tasks.
    private var tasks: some View {
        SwiftUI.Section("Tasks") {
            Label("Firmwares", systemImage: "arrow.left.arrow.right")
                .tag(Section.firmwares)
                .listItemTint(Palette.firmwaresTint)
            Label("My firmwares", systemImage: "star")
                .tag(Section.mine)
                .listItemTint(Palette.accent)
            // Kept while it's open, so unplugging doesn't snatch the page away.
            if model.offersSaveMyFM1 || section == .save {
                Label("Save my FM-1", systemImage: "square.and.arrow.down")
                    .tag(Section.save)
                    .listItemTint(Palette.save)
            }
            #if os(macOS)
                Label("Backup & rescue", systemImage: "externaldrive.badge.checkmark")
                    .tag(Section.downloadMode)
                    .listItemTint(Palette.accent)
            #endif
        }
    }

    private func select(_ entry: CatalogueEntry) {
        withAnimation(Motion.standard) { selectedFirmwareID = entry.id }
    }

    /// A firmware list with the picked firmware beside it.
    private func sideBySide(@ViewBuilder list: () -> some View) -> some View {
        HStack(spacing: 0) {
            list()
                .frame(width: 380)
            Divider()
            Group {
                if let id = selectedFirmwareID, let entry = model.catalogue.entry(id: id) {
                    FirmwarePageView(listed: entry)
                        .id(id)
                        .transition(.opacity)
                } else {
                    ContentUnavailableView(
                        "Choose a firmware",
                        systemImage: "arrow.left.arrow.right",
                        description: Text("Pick one from the list to read about it and install it."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.ground)
        }
    }

    #if DEBUG
        /// Debug builds accept `-openPage firmwares`, `-openPage mine`, `-openPage save`, `-openPage downloadMode`,
        /// `-openPage help` or `-openPage settings` as a launch argument with the sidebar, for
        /// screenshots.
        private func openSectionFromLaunchArguments() {
            switch UserDefaults.standard.string(forKey: "openPage") {
            case "firmwares": section = .firmwares
            case "mine": section = .mine
            case "save": section = .save
            case "downloadMode": section = .downloadMode
            case "help": section = .help
            case "settings": section = .settings
            default: break
            }
        }

        /// Debug builds accept `-openPage firmwares`, `-openPage mine`, `-openPage save`, `-openPage help`,
        /// `-openPage settings` or `-openPage <firmware ID>` as a launch argument on iPhone, for
        /// screenshots.
        private func openPageFromLaunchArguments() async {
            guard let page = UserDefaults.standard.string(forKey: "openPage") else { return }
            switch page {
            case "firmwares": path = [.firmwares]
            case "mine": path = [.mine]
            case "save": path = [.save]
            case "help": path = [.help(nil)]
            case "settings": path = [.settings]
            default:
                while model.catalogue.entry(id: page) == nil {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                if let entry = model.catalogue.entry(id: page) { path = [.firmwares, .firmware(entry)] }
            }
        }
    #endif
}
