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

    /// The kinds the lists give `entries`, such as "synth" or "groove", the most common first.
    ///
    /// They come from the lists as they are today, so a new kind gets a filter without an app
    /// update. Firmwares the lists don't sort only show under All.
    nonisolated static func kinds(of entries: [CatalogueEntry]) -> [String] {
        let counts = entries.reduce(into: [String: Int]()) { counts, entry in
            for kind in Set(entry.kinds.map { $0.lowercased() }) { counts[kind, default: 0] += 1 }
        }
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
    }

    /// Whether the lists give `entry` this kind.
    nonisolated static func isKind(_ kind: String, _ entry: CatalogueEntry) -> Bool {
        entry.kinds.contains { $0.caseInsensitiveCompare(kind) == .orderedSame }
    }

    /// The firmware hub's names for its kinds, so the filters match the hub's.
    nonisolated private static let kindNames = [
        "synth": "Synths", "groove": "Grooveboxes", "drums": "Drums & samplers", "chords": "Chords",
        "tracker": "Trackers", "dev": "For devs", "other": "Other", "game": "Games",
    ]

    /// A kind as a filter's name: "groove" as "Grooveboxes", as the firmware hub names it, or
    /// "platform" as "Platform" for one it doesn't.
    nonisolated static func name(of kind: String) -> String {
        kindNames[kind.lowercased()] ?? kind.prefix(1).uppercased() + kind.dropFirst()
    }

    /// The filters a list offers: All, Saved when asked for, a filter for each kind the lists give
    /// (the most common first), and Built from source when any firmware is.
    nonisolated static func scopes(for entries: [CatalogueEntry], includingSaved: Bool) -> [FirmwareScope] {
        var scopes: [FirmwareScope] = includingSaved ? [.all, .saved] : [.all]
        scopes += kinds(of: entries).map(FirmwareScope.kind)
        if entries.contains(where: \.isBuiltFromSource) { scopes.append(.builtFromSource) }
        return scopes
    }

    private func matches(_ entry: CatalogueEntry) -> Bool {
        search.isEmpty
            || entry.name.localizedCaseInsensitiveContains(search)
            || (entry.what ?? "").localizedCaseInsensitiveContains(search)
            || (entry.author ?? "").localizedCaseInsensitiveContains(search)
            || entry.kinds.contains { $0.localizedCaseInsensitiveContains(search) }
    }
}

/// One of a firmware list's quick filters.
enum FirmwareScope: Hashable {
    case all
    /// Firmwares with a copy saved here.
    case saved
    /// Firmwares the lists give this kind, such as "synth".
    case kind(String)
    /// Firmwares built from their source by GitHub Actions, as a signed record says.
    case builtFromSource

    var name: String {
        switch self {
        case .all: "All"
        case .saved: "Saved"
        case .kind(let kind): FirmwareFilter.name(of: kind)
        case .builtFromSource: "Built from source"
        }
    }

    @MainActor
    func includes(_ entry: CatalogueEntry, in model: AppModel) -> Bool {
        switch self {
        case .all: true
        case .saved: FirmwareFilter.isSaved(entry, in: model)
        case .kind(let kind): FirmwareFilter.isKind(kind, entry)
        case .builtFromSource: entry.isBuiltFromSource
        }
    }
}
