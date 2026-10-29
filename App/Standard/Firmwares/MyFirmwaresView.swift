import SwiftUI

/// The firmwares saved here, and the ones starred to come back to, in the firmware list's cards.
struct MyFirmwaresView: View {
    @Environment(AppModel.self) private var model
    /// The firmware showing beside the list, when there's room for it.
    var selectedID: String?
    var onSelect: (CatalogueEntry) -> Void

    /// The listed firmwares saved here, an older release included, then the ones added from files
    /// that no list describes.
    private var saved: [CatalogueEntry] {
        model.catalogue.entries.filter { entry in
            FirmwareFilter.isSaved(entry, in: model) || model.library.outdated(for: entry) != nil
        } + model.addedFromFiles
    }

    /// Starred and not saved: a saved one is listed with the saved ones, with its star.
    private var starred: [CatalogueEntry] {
        model.catalogue.entries.filter { entry in
            model.starred.contains(entry.id) && !FirmwareFilter.isSaved(entry, in: model)
                && model.library.outdated(for: entry) == nil
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                group("Saved on this \(ThisDevice.name)", saved, empty: Self.savedEmpty)
                group("Starred", starred, empty: Self.starredEmpty)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(Motion.standard, value: starred.map(\.id))
        }
        .background(Palette.ground)
        .navigationTitle("My firmwares")
        .refreshable { await model.catalogue.refresh() }
    }

    @ViewBuilder
    private func group(_ title: String, _ entries: [CatalogueEntry], empty: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
        ForEach(entries) { entry in
            Button {
                onSelect(entry)
            } label: {
                FirmwareCard(entry: entry, isSelected: entry.id == selectedID)
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("firmware")
        }
        if entries.isEmpty {
            Text(empty)
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, 4)
        }
    }

    static let savedEmpty = """
        Firmwares you download or add with + appear here, ready to install even when you're offline.
        """
    static let starredEmpty = "Star a firmware on its page to keep it here without downloading it."
}
