import FM1Kit
import SwiftUI

/// The firmware list from the hub, with a refresh button and per-firmware status.
struct CatalogueView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.phosphor) private var theme
    @Environment(\.isWideLayout) private var isWide
    @State private var search = ""
    @State private var scope = FirmwareScope.all
    @State private var selected: CatalogueEntry?
    @FocusState private var isSearchFocused: Bool
    /// The firmware to open at, by catalogue ID.
    var opening: String?

    private var filter: FirmwareFilter { FirmwareFilter(search: search) }

    private var visibleEntries: [CatalogueEntry] {
        model.settings.firmwareOrder.sorted(filter.visible(in: model).filter { scope.includes($0) })
    }

    var body: some View {
        Group {
            if isWide {
                ListAndDetail(placeholder: "Pick a firmware from the list.", hasSelection: selected != nil) {
                    listColumn
                } detail: {
                    if let selected {
                        FirmwareDetailView(entry: selected, isInPane: true)
                            .id(selected.id)
                    }
                }
            } else {
                // A page of its own, so swiping from the left edge goes back.
                NavigationStack {
                    listColumn
                        .background(theme.background.ignoresSafeArea())
                        .hidesNavigationBar()
                        .navigationDestination(item: $selected) { entry in
                            FirmwareDetailView(entry: entry)
                                .hidesNavigationBar()
                        }
                }
            }
        }
        .task(id: opening) {
            if let opening, let entry = model.catalogue.entry(id: opening) { selected = entry }
        }
        #if DEBUG
            // `-openFirmware <id>` opens a firmware's page at launch, for screenshots, once the list
            // the app downloads as it opens has arrived.
            .task {
                guard let id = UserDefaults.standard.string(forKey: "openFirmware") else { return }
                while model.catalogue.entry(id: id) == nil {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                selected = model.catalogue.entry(id: id)
            }
        #endif
    }

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenHeader(title: "FIRMWARE") {
                Button(model.catalogue.isRefreshing ? "LOADING" : "REFRESH") {
                    Task { await model.catalogue.refresh() }
                }
                .buttonStyle(.pixelCompact)
                .disabled(model.catalogue.isRefreshing)
            }

            searchField
            kindFilter
            statusLine
            firmwareList
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Text(">").font(.mono(17)).foregroundStyle(theme.bright)
            TextField("", text: $search, prompt: Text("SEARCH").foregroundStyle(theme.muted))
                .font(.mono(15))
                .foregroundStyle(theme.ink)
                .tint(theme.bright)
                .plainTextEntry()
                .focused($isSearchFocused)
                // The box shows focus instead of the system's rounded ring.
                .focusEffectDisabled()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(PixelBox().fill(theme.surface))
        .overlay(PixelBox().strokeBorder(isSearchFocused ? theme.bright : theme.dim, lineWidth: 2))
    }

    /// The order, then ALL, a filter for each kind the lists give (the most common first), and BUILT
    /// FROM SOURCE.
    private var kindFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                orderButton
                let scopes = FirmwareFilter.scopes(for: FirmwareFilter().visible(in: model))
                ForEach(scopes, id: \.self) { scopeButton($0) }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    /// Switches between the orders, saying which it's in: "SORT: NAME".
    private var orderButton: some View {
        @Bindable var settings = model.settings
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                settings.firmwareOrder = settings.firmwareOrder == .name ? .updated : .name
            }
        } label: {
            Text("SORT: \(settings.firmwareOrder.name.uppercased())")
                .font(.pixel(9, bold: true, relativeTo: .caption2))
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .foregroundStyle(theme.ink)
                .background(theme.surface)
                .overlay(PixelBox().strokeBorder(theme.dim, lineWidth: 2))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(settings.firmwareOrder.name)")
    }

    private func scopeButton(_ option: FirmwareScope) -> some View {
        let isChosen = scope == option
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { scope = option }
        } label: {
            Text(option.name.uppercased())
                .font(.pixel(9, bold: true, relativeTo: .caption2))
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .foregroundStyle(isChosen ? theme.background : theme.bright)
                .background(isChosen ? theme.bright : theme.surface)
                .overlay(PixelBox().strokeBorder(isChosen ? theme.bright : theme.faint, lineWidth: 2))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var firmwareList: some View {
        PixelRefreshScrollView(isRefreshing: model.catalogue.isRefreshing) {
            await model.catalogue.refresh()
        } content: {
            LazyVStack(spacing: 8) {
                ForEach(visibleEntries) { entry in
                    Button {
                        selected = entry
                    } label: {
                        CatalogueRow(entry: entry, isSelected: isWide && selected?.id == entry.id)
                    }
                    .buttonStyle(.plain)
                }
                linksOnlyFooter
            }
            .padding(.bottom, 16)
        }
    }

    /// Says how many links-only firmwares are hidden, with a switch to show or hide them.
    @ViewBuilder
    private var linksOnlyFooter: some View {
        let linksOnly = filter.matching(in: model).filter { !FirmwareFilter.isInstallable($0, in: model) }.count
        if linksOnly > 0 {
            VStack(alignment: .leading, spacing: 8) {
                NoteText(linksOnlyMessage(count: linksOnly))
                Button(model.settings.showLinksOnly ? "HIDE LINKS-ONLY" : "SHOW LINKS-ONLY (\(linksOnly))") {
                    model.settings.showLinksOnly.toggle()
                }
                .buttonStyle(.pixelCompact)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }

    private func linksOnlyMessage(count: Int) -> String {
        if model.settings.showLinksOnly {
            return "Showing \(count) links-only firmware\(count == 1 ? "" : "s") (no file to download)."
        }
        return count == 1
            ? "1 more firmware has no file to download, only links to its site."
            : "\(count) more firmwares have no file to download, only links to their sites."
    }

    @ViewBuilder
    private var statusLine: some View {
        let count = visibleEntries.count
        VStack(alignment: .leading, spacing: 2) {
            if let catalogue = model.catalogue.catalogue {
                let checked = catalogue.builtAt.formatted(date: .abbreviated, time: .shortened).uppercased()
                MonoText("\(count) FIRMWARES · CHECKED \(checked)", size: 12, dim: true)
                ForEach(catalogue.problems, id: \.self) { problem in
                    MonoText(problem, size: 12)
                }
            }
            if let error = model.catalogue.errorMessage {
                MonoText(error, size: 12)
            } else if model.catalogue.catalogue == nil && !model.catalogue.isRefreshing {
                MonoText("No list saved yet. Tap REFRESH while online.", size: 12)
            }
        }
    }
}

private struct CatalogueRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.phosphor) private var theme
    var entry: CatalogueEntry
    /// Whether the row's firmware is showing beside the list.
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
            if let what = entry.what {
                Text(what)
                    .font(.mono(13))
                    .lineSpacing(3)
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            tags
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixelBox().fill(theme.surface))
        .overlay(PixelBox().strokeBorder(isSelected ? theme.bright : theme.faint, lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.name.uppercased())
                .font(.pixel(14, bold: true, relativeTo: .headline))
                .foregroundStyle(theme.bright)
                .phosphorGlow(0.6)
            Spacer()
            Text(entry.version ?? "")
                .font(.mono(13))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
        }
    }

    private var tags: some View {
        HStack(spacing: 6) {
            if entry.isOfficial { PixelTag(text: "OFFICIAL") }
            if FirmwareFilter.isSaved(entry, in: model) {
                PixelTag(text: "SAVED")
            } else if model.library.outdated(for: entry) != nil {
                PixelTag(text: "UPDATE")
            }
            if !entry.isDownloadable { PixelTag(text: "LINKS ONLY", inverted: false) }
            // Not known to work on an FM-1 says more than a test release, so only that shows.
            if !entry.isHardwareTested {
                PixelTag(text: "IN TESTING", inverted: false)
            } else if entry.beta {
                PixelTag(text: "BETA", inverted: false)
            }
            if entry.requiresOfficialFirmware { PixelTag(text: "VIA OFFICIAL", inverted: false) }
            if model.device.identity?.text == entry.product { PixelTag(text: "ID MATCH", inverted: false) }
            Spacer()
            if let author = entry.author {
                Text(author.uppercased())
                    .font(.pixel(8, relativeTo: .caption2))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
        }
    }
}
