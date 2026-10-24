import SwiftUI
import UniformTypeIdentifiers

/// The firmware list: the heart of the app.
///
/// Search, a few filters, and a card for each firmware.
struct FirmwareListView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var scope = FirmwareScope.all
    @State private var isImporting = false
    @State private var importMessage: String?
    /// The firmware showing beside the list, when there's room for it.
    var selectedID: String?
    var onSelect: (CatalogueEntry) -> Void

    private var entries: [CatalogueEntry] {
        FirmwareFilter(search: search).visible(in: model).filter { scope.includes($0, in: model) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                scopePicker
                summary
                ForEach(entries) { entry in
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
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(Motion.standard, value: scope)
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

    private var scopes: [FirmwareScope] {
        FirmwareFilter.scopes(for: FirmwareFilter().visible(in: model), includingSaved: true)
    }

    private var scopePicker: some View {
        ScrollView(.horizontal) {
            scopeButtons
        }
        .scrollIndicators(.hidden)
        // The row runs to the screen's edges, and its buttons line up with the cards below.
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
    }

    private var scopeButtons: some View {
        HStack(spacing: 8) {
            ForEach(scopes, id: \.self) { option in
                let isPicked = option == scope
                Button(option.name) {
                    withAnimation(Motion.standard) { scope = option }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .foregroundStyle(isPicked ? Palette.card : Palette.ink)
                .background(Capsule().fill(isPicked ? Palette.ink : Palette.control))
                .buttonStyle(.pressable)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
            }
        }
        .padding(.top, 4)
    }

    /// How many firmwares there are, and when the list was last checked.
    @ViewBuilder private var summary: some View {
        let catalogue = model.catalogue
        VStack(alignment: .leading, spacing: 2) {
            if catalogue.isRefreshing && catalogue.catalogue == nil {
                Text("Getting the firmware list…")
            } else {
                Text("^[\(entries.count) firmware](inflect: true)")
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
        }
        .font(.footnote)
        .foregroundStyle(Palette.secondaryInk)
        .padding(.horizontal, 4)
        .animation(Motion.fade, value: entries.count)
    }

    @ViewBuilder private var emptyMessage: some View {
        let message =
            switch scope {
            case .saved: "Firmwares you download appear here, ready to install even when you're offline."
            default: search.isEmpty ? "No firmwares to show yet." : "Nothing matches “\(search)”."
            }
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
                item.source == .official
                ? "Added M-VAVE's official firmware."
                : "Added \(item.name). It isn't in the firmware list, so check where it came from before installing it."
        } catch {
            importMessage = error.localizedDescription
        }
    }
}

/// One firmware in the list.
private struct FirmwareCard: View {
    @Environment(AppModel.self) private var model
    var entry: CatalogueEntry
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FirmwareBadge(design: model.catalogue.badge(id: entry.id, name: entry.name))
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    // At its full width, or the name is cut short instead of the row wrapping.
                    HStack(alignment: .firstTextBaseline, spacing: 8) { title }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) { title }
                }
                if let what = entry.what {
                    Text(what)
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

    @ViewBuilder private var title: some View {
        Text(entry.name)
            .font(.headline)
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.leading)
        if let version = entry.version {
            Text(version)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
        }
        tags
    }

    @ViewBuilder private var tags: some View {
        if isOnFM1 {
            Tag(text: "On your FM-1", ink: Palette.goodInk, fill: Palette.goodBackground)
        } else if entry.isOfficial {
            Tag(text: "Official", ink: Palette.ink, fill: Palette.control)
        } else if FirmwareFilter.isSaved(entry, in: model) {
            Tag(text: "Saved", ink: Palette.ink, fill: Palette.control)
        }
        if entry.beta { Tag(text: "Test version", ink: Palette.warningInk, fill: Palette.warningBackground) }
        if !entry.isHardwareTested { Tag(text: "In testing", ink: Palette.warningInk, fill: Palette.warningBackground) }
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
