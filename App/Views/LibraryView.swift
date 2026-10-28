import SwiftUI
import UniformTypeIdentifiers

/// Firmwares saved on the phone for offline flashing, the official firmware, and the cache.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.phosphor) private var theme
    @Environment(\.isWideLayout) private var isWide
    @State private var importing = false
    /// The saved firmware showing beside the list, in the wide layout.
    @State private var selectedID: String?
    /// The starred firmware showing beside the list, or opened on a page of its own.
    @State private var openedStar: CatalogueEntry?
    @State private var officialLink = ""
    @FocusState private var isLinkFocused: Bool
    @State private var message: String?
    @State private var busy = false
    @State private var confirmingClear = false
    @State private var flashing: StoredFirmware?

    private var library: FirmwareLibrary { model.library }

    /// Saved catalogue firmwares that have a newer release in the list.
    private var updatable: [CatalogueEntry] {
        model.catalogue.entries.filter { library.outdated(for: $0) != nil }
    }

    /// The picked saved firmware, or the official one until something is picked.
    private var selected: StoredFirmware? {
        library.items.first { $0.id == selectedID } ?? library.official
    }

    /// Starred firmwares that aren't saved: a saved one is with the saved ones.
    private var starred: [CatalogueEntry] {
        model.catalogue.entries.filter { model.starred.contains($0.id) && !FirmwareFilter.isSaved($0, in: model) }
    }

    var body: some View {
        Group {
            if isWide {
                ListAndDetail(
                    placeholder: "Pick a saved firmware from the list.",
                    hasSelection: openedStar != nil || selected != nil
                ) {
                    listColumn
                } detail: {
                    if let openedStar {
                        FirmwareDetailView(entry: openedStar, isInPane: true)
                            .id(openedStar.id)
                    } else if let selected {
                        detail(of: selected)
                            .id(selected.id)
                    }
                }
            } else {
                // A page of its own for a starred firmware, so swiping from the left edge goes back.
                NavigationStack {
                    listColumn
                        .background(theme.background.ignoresSafeArea())
                        .hidesNavigationBar()
                        .navigationDestination(item: $openedStar) { entry in
                            FirmwareDetailView(entry: entry)
                                .hidesNavigationBar()
                        }
                }
            }
        }
        .fileImporter(
            isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "fwsc") ?? .data, .data]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let item = try library.importFile(at: url)
                    message =
                        item.source == .official
                        ? "Official firmware verified and saved."
                        : """
                        Saved \(item.name) (\(item.product)). It isn't in the catalogue, \
                        so check where it came from.
                        """
                } catch {
                    message = error.localizedDescription
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .sheet(item: $flashing) { item in
            FlashConfirmView(
                target: item,
                requiresOfficial: item.catalogueID.flatMap(model.catalogue.entry(id:))?.requiresOfficialFirmware
                    ?? false
            )
            .environment(model)
            .environment(\.phosphor, theme)
            .pixelSheetSize()
            .presentationBackground(theme.background)
        }
        .confirmationDialog("Clear saved firmwares?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { library.clear() }
        } message: {
            Text("The official firmware stays. The rest can be downloaded again while online.")
        }
    }

    /// The official firmware, the saved ones and storage, which list beside the picked one when wide.
    private var listColumn: some View {
        // Pulling down refreshes the firmware list, which shows which saved firmwares have updates.
        PixelRefreshScrollView(isRefreshing: model.catalogue.isRefreshing) {
            await model.catalogue.refresh()
        } content: {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: "SAVED")
                officialPanel
                savedPanel
                RetroStarredPanel(starred: starred, openedStar: $openedStar)
                storagePanel
                if let message {
                    MonoText(message, size: 14)
                }
            }
            .padding(16)
        }
    }

    /// A saved firmware's catalogue page when it has one, otherwise what the package says.
    @ViewBuilder private func detail(of item: StoredFirmware) -> some View {
        if let entry = item.catalogueID.flatMap(model.catalogue.entry(id:)) {
            FirmwareDetailView(entry: entry, isInPane: true)
        } else {
            SavedFirmwareDetail(item: item, onFlash: { flashing = item })
        }
    }

    /// The name of a saved firmware, which picks it in the wide layout.
    @ViewBuilder private func itemTitle(_ item: StoredFirmware) -> some View {
        let title = VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(item.name.uppercased())
                if isStarred(item) {
                    Text("★").accessibilityLabel("Starred")
                }
            }
            .font(.pixel(12, bold: true, relativeTo: .headline))
            .foregroundStyle(theme.bright)
            .phosphorGlow(0.7)
            MonoText(summary(of: item), size: 14, dim: true)
            MonoText("Saved \(item.savedAt.formatted(date: .abbreviated, time: .omitted))", size: 13, dim: true)
        }
        if isWide {
            Button {
                openedStar = nil
                selectedID = item.id
            } label: {
                // As wide as the row allows, so a click anywhere beside the buttons picks it.
                title
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected?.id == item.id ? .isSelected : [])
        } else {
            title
        }
    }

    /// One line describing a saved firmware: version, build, identity and size.
    private func summary(of item: StoredFirmware) -> String {
        [item.version, item.build.map { "\($0) build" }, item.product, formattedBytes(item.size)]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private var officialPanel: some View {
        PixelPanel(title: "OFFICIAL FIRMWARE") {
            if let official = library.official {
                if isWide {
                    officialRow(official)
                } else {
                    HStack {
                        MonoText("✓ \(official.name)", size: 17)
                        Spacer()
                        PixelTag(text: official.product)
                    }
                }
                NoteText("Comes with the app, checked against the known checksum. Kept when you clear the cache.")
                Button("FLASH OFFICIAL") { flashing = official }
                    .buttonStyle(.pixel)
            } else {
                officialMissing
            }
        }
    }

    /// The official firmware, which picks it in the wide layout.
    private func officialRow(_ official: StoredFirmware) -> some View {
        HStack {
            Button {
                openedStar = nil
                selectedID = official.id
            } label: {
                Text("✓ \(official.name)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.mono(17))
            .foregroundStyle(theme.ink)
            .accessibilityAddTraits(selected?.id == official.id ? .isSelected : [])
            PixelTag(text: official.product)
        }
        .rowBox(isPicked: openedStar == nil && selected?.id == official.id, theme: theme)
    }

    @ViewBuilder private var officialMissing: some View {
        MonoText(
            """
            The copy that comes with the app couldn't be saved. Download FM-1 V15 (FM-1.fwsc) straight \
            from M-VAVE's site, or import a copy you already have. Either way it's checked against the \
            known checksum.
            """,
            size: 14
        )
        Button(busy ? "DOWNLOADING…" : "GET FROM M-VAVE") { Task { await fetchOfficialFromMVAVE() } }
            .buttonStyle(.pixelProminent)
            .disabled(busy)
        Button("IMPORT FROM FILES") { importing = true }
            .buttonStyle(.pixel)
        HStack(spacing: 8) {
            TextField("", text: $officialLink, prompt: Text("OR PASTE A DOWNLOAD LINK").foregroundStyle(theme.muted))
                .font(.mono(14))
                .foregroundStyle(theme.ink)
                .tint(theme.bright)
                .plainTextEntry(forLinks: true)
                .focused($isLinkFocused)
                // The box shows focus instead of the system's rounded ring.
                .focusEffectDisabled()
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(PixelBox(step: 2).fill(theme.background))
                .overlay(PixelBox(step: 2).strokeBorder(isLinkFocused ? theme.bright : theme.dim, lineWidth: 2))
            Button(busy ? "…" : "GET") { Task { await fetchOfficial() } }
                .buttonStyle(.pixelCompact)
                .disabled(busy || URL(string: officialLink)?.scheme == nil)
        }
    }

    private var savedPanel: some View {
        PixelPanel(title: "ON THIS \(ThisDevice.name.uppercased())") {
            let items = library.sortedItems.filter { $0.source != .official }
            if items.isEmpty {
                MonoText(
                    "Nothing saved. Save firmwares from the FIRMWARE list to flash them offline.", size: 14, dim: true)
            }
            ForEach(items) { item in
                let isPicked = isWide && openedStar == nil && selected?.id == item.id
                HStack(alignment: .center, spacing: 10) {
                    itemTitle(item)
                    Spacer()
                    Button("FLASH") { flashing = item }
                        .buttonStyle(.pixelCompact)
                    if library.canRemove(item) {
                        Button("✕") { library.remove(item) }
                            .buttonStyle(.pixelCompact)
                            .accessibilityLabel("Remove \(item.name)")
                    }
                }
                .rowBox(isPicked: isPicked, theme: theme)
            }
            Button("IMPORT .FWSC FROM FILES") { importing = true }
                .buttonStyle(.pixel)
        }
    }

    private var storagePanel: some View {
        PixelPanel(title: "STORAGE") {
            let count = library.items.count
            MonoText("\(count) FILE\(count == 1 ? "" : "S") · \(formattedBytes(library.totalBytes))", size: 15)
            if !updatable.isEmpty {
                MonoText(
                    "\(updatable.count) saved firmware\(updatable.count == 1 ? " has" : "s have") a newer release.",
                    size: 13)
                Button(busy ? "UPDATING…" : "DOWNLOAD UPDATES") { Task { await downloadUpdates() } }
                    .buttonStyle(.pixel)
                    .disabled(busy)
            }
            Button("CLEAR CACHE") { confirmingClear = true }
                .buttonStyle(.pixel)
                .disabled(library.items.allSatisfy { $0.source == .official })
        }
    }

    private func fetchOfficial() async {
        guard let url = URL(string: officialLink) else { return }
        busy = true
        defer { busy = false }
        do {
            try await library.importOfficial(from: url)
            message = "Official firmware verified and saved."
            officialLink = ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func fetchOfficialFromMVAVE() async {
        busy = true
        defer { busy = false }
        do {
            try await library.downloadOfficialFromMVAVE()
            message = "Official firmware downloaded from M-VAVE, verified and saved."
        } catch {
            message = error.localizedDescription
        }
    }

    private func downloadUpdates() async {
        busy = true
        defer { busy = false }
        var failures = 0
        for entry in updatable {
            do {
                try await library.download(entry)
            } catch {
                failures += 1
            }
        }
        message =
            failures == 0
            ? "Saved firmwares are up to date."
            : "\(failures) update\(failures == 1 ? "" : "s") failed. Refresh the list and try again."
    }
}

extension LibraryView {
    /// Whether a saved firmware is starred, which leaves it here rather than under STARRED.
    fileprivate func isStarred(_ item: StoredFirmware) -> Bool {
        model.catalogue.entries.contains { entry in
            model.starred.contains(entry.id)
                && (library.stored(for: entry)?.id == item.id || library.otherBuild(for: entry)?.id == item.id)
        }
    }
}
