import Foundation

/// Which firmwares a list shows: the settings' beta and links-only choices, plus a search.
@MainActor
struct FirmwareFilter {
    var search = ""

    /// Entries passing the beta and search filters, before links-only ones are hidden.
    func matching(in model: AppModel) -> [CatalogueEntry] {
        model.catalogue.entries.filter { entry in
            (model.settings.showBeta || !entry.beta) && matches(entry)
        }
    }

    /// What the list shows: the matching entries, without links-only ones unless the settings
    /// ask for them.
    func visible(in model: AppModel) -> [CatalogueEntry] {
        matching(in: model).filter { model.settings.showLinksOnly || Self.isInstallable($0, in: model) }
    }

    /// Downloadable, or already saved here (a saved copy can be installed even if its download
    /// has since disappeared).
    static func isInstallable(_ entry: CatalogueEntry, in model: AppModel) -> Bool {
        entry.isDownloadable || model.library.items.contains { $0.catalogueID == entry.id }
    }

    /// Whether a copy of `entry` is saved here.
    static func isSaved(_ entry: CatalogueEntry, in model: AppModel) -> Bool {
        model.library.stored(for: entry) != nil || model.library.otherBuild(for: entry) != nil
    }

    private func matches(_ entry: CatalogueEntry) -> Bool {
        search.isEmpty
            || entry.name.localizedCaseInsensitiveContains(search)
            || (entry.what ?? "").localizedCaseInsensitiveContains(search)
            || (entry.author ?? "").localizedCaseInsensitiveContains(search)
            || entry.kinds.contains { $0.localizedCaseInsensitiveContains(search) }
    }
}
