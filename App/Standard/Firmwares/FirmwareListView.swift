import SwiftUI
import UniformTypeIdentifiers

/// The firmware list: the heart of the app.
///
/// Search, a few filters, and a card for each firmware.
struct FirmwareListView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var isImporting = false
    @State private var importMessage: String?
    /// The firmware showing beside the list, when there's room for it.
    var selectedID: String?
    /// Whether picked firmwares show beside the list, so the arrow keys can step through it.
    var isBesidePage = false
    var onSelect: (CatalogueEntry) -> Void

    /// The firmwares to show under `scope`, in order.
    ///
    /// It goes through the whole list, so work it out once a pass.
    private func entries(in scope: FirmwareScope) -> [CatalogueEntry] {
        model.settings.firmwareOrder.sorted(
            FirmwareFilter(search: search).visible(in: model).filter { scope.includes($0) })
    }

    var body: some View {
        @Bindable var settings = model.settings
        // From the whole list, not the search, so a search doesn't take filters away.
        let scopes = FirmwareFilter.scopes(for: FirmwareFilter().visible(in: model))
        // The list's own filter, which is the one picked unless it's no longer offered.
        let shown = entries(in: settings.firmwareScope.offered(in: scopes))
        FilteredFirmwareList(
            order: $settings.firmwareOrder,
            scope: $settings.firmwareScope,
            scopes: scopes,
            stepping: isBesidePage ? ArrowKeySteps(entries: shown, selectedID: selectedID, select: onSelect) : nil
        ) { _ in
            list(shown)
        }
        .background(Palette.ground)
        .navigationTitle("Firmwares")
        .searchable(text: $search, prompt: "Search \(FirmwareFilter().visible(in: model).count) firmwares")
        .refreshable { await model.catalogue.refresh() }
        .toolbar { toolbar }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "fwsc") ?? .data],
            onCompletion: importFile
        )
        .alert(
            "Firmware file",
            isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } }),
            presenting: importMessage
        ) { _ in
            Button("OK") { importMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder private func list(_ entries: [CatalogueEntry]) -> some View {
        summary(count: entries.count)
        let firstUncounted = model.settings.firmwareOrder.firstUncounted(in: entries)
        ForEach(entries) { entry in
            if entry.id == firstUncounted { uncountedNote }
            Button {
                onSelect(entry)
            } label: {
                FirmwareCard(entry: entry, isSelected: entry.id == selectedID)
            }
            .buttonStyle(.pressable)
            // For UI tests, which open a firmware from the list.
            .accessibilityIdentifier("firmware")
        }
        if entries.isEmpty { emptyMessage }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            #if os(macOS)
                Button {
                    Task { await model.catalogue.refresh() }
                } label: {
                    Label("Check for new firmwares", systemImage: "arrow.clockwise")
                }
                .disabled(model.catalogue.isRefreshing)
            #endif
            Button {
                isImporting = true
            } label: {
                Label("Add a firmware file", systemImage: "plus")
            }
        }
    }

    /// How many firmwares there are, and when the list was last checked.
    @ViewBuilder private func summary(count: Int) -> some View {
        let catalogue = model.catalogue
        VStack(alignment: .leading, spacing: 2) {
            if catalogue.isRefreshing && catalogue.catalogue == nil {
                Text("Getting the firmware list…")
            } else {
                Text("^[\(count) firmware](inflect: true)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
            }
            if let builtAt = catalogue.catalogue?.builtAt {
                Text("List updated \(builtAt.formatted(.relative(presentation: .named)))")
            }
            if let error = catalogue.errorMessage {
                Text(error)
            }
            if model.settings.firmwareOrder == .installs {
                Text(FirmwareOrder.installsSource)
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.secondaryInk)
        .padding(.horizontal, 4)
        .animation(Motion.fade, value: count)
    }

    /// Under Most installed, between the firmwares The Firmware Hub counts and the rest.
    private var uncountedNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Palette.line)
            Text(FirmwareOrder.uncountedNote)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, 4)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var emptyMessage: some View {
        let message = search.isEmpty ? "No firmwares to show yet." : "Nothing matches “\(search)”."
        Text(message)
            .font(.callout)
            .foregroundStyle(Palette.secondaryInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    private func importFile(_ result: Result<URL, any Error>) {
        do {
            let item = try model.library.importFile(at: result.get())
            importMessage =
                if item.source == .official {
                    "Added M-VAVE's official firmware."
                } else if model.catalogue.entries.contains(where: { $0.sha256 == item.sha256 }) {
                    "Added \(item.name) to My firmwares."
                } else {
                    """
                    Added \(item.name) to My firmwares. It isn't in the firmware lists, so check where it came \
                    from before installing it.
                    """
                }
        } catch {
            importMessage = error.localizedDescription
        }
    }
}

/// One firmware in the list.
struct FirmwareCard: View {
    @Environment(AppModel.self) private var model
    var entry: CatalogueEntry
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FirmwareBadge(design: model.catalogue.badge(id: entry.id, name: entry.name))
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    // At its full width, or the name is cut short instead of the row wrapping.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        name
                        details
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    // The name and its star together, then the version and tags.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) { name }
                        HStack(alignment: .firstTextBaseline, spacing: 8) { details }
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    // Narrower still, the tags get a line of their own, and only the version is cut short.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) { name }
                        version
                        HStack(spacing: 8) { tags }
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                if let what = entry.what {
                    Text(FirmwareDescription.styled(what))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        // A summary, cut short on purpose: the accessibility audit allows it.
                        .accessibilityIdentifier("summary")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Palette.firmwaresTint : .clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var name: some View {
        Text(entry.name)
            .font(.headline)
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.leading)
        if model.starred.contains(entry.id) {
            Image(systemName: "star.fill")
                .font(.footnote)
                .foregroundStyle(Palette.accent)
                .accessibilityLabel("Starred")
        }
    }

    @ViewBuilder private var details: some View {
        version
        tags
    }

    @ViewBuilder private var version: some View {
        if let version = entry.version {
            Text(version)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var tags: some View {
        if isOnFM1 {
            Tag(text: "On your FM-1", ink: Palette.goodInk, fill: Palette.goodBackground)
        } else if entry.isOfficial {
            Tag(text: "Official", ink: Palette.ink, fill: Palette.control)
        } else if model.library.outdated(for: entry) != nil {
            Tag(text: "Update", ink: Palette.goodInk, fill: Palette.goodBackground)
        } else if FirmwareFilter.isSaved(entry, in: model) {
            let count = model.library.savedCopies(of: entry).count
            Tag(text: count > 1 ? "\(count) saved" : "Saved", ink: Palette.ink, fill: Palette.control)
        }
        // Not known to work on an FM-1 says more than a test release, so only that shows.
        if entry.isFromFile {
            Tag(text: "From a file", ink: Palette.warningInk, fill: Palette.warningBackground)
        } else if !entry.isHardwareTested {
            Tag(text: "In testing", ink: Palette.warningInk, fill: Palette.warningBackground)
        } else if entry.beta {
            Tag(text: "Test version", ink: Palette.warningInk, fill: Palette.warningBackground)
        }
    }

    /// Whether the FM-1 is running this, as far as anyone can tell: it reports this firmware's
    /// identity, and either this app installed it or no other listed firmware reports the same.
    private var isOnFM1: Bool {
        guard let identity = model.device.identity?.text, identity == entry.product else { return false }
        if let last = model.history.lastInstall(matching: identity) { return last.name == entry.name }
        return model.catalogue.entries(matching: identity).count == 1
    }
}

/// A small label on a card.
struct Tag: View {
    var text: String
    var ink: Color
    var fill: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(fill))
            .lineLimit(1)
    }
}
