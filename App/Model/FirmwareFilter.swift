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
        !model.library.savedCopies(of: entry).isEmpty && model.library.outdated(for: entry) == nil
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

    /// The Firmware Hub's names for its kinds, so the filters match the hub's.
    nonisolated private static let kindNames = [
        "synth": "Synths", "groove": "Grooveboxes", "drums": "Drums & samplers", "chords": "Chords",
        "tracker": "Trackers", "dev": "For devs", "other": "Other", "game": "Games",
    ]

    /// A kind as a filter's name: "groove" as "Grooveboxes", as The Firmware Hub names it, or
    /// "platform" as "Platform" for one it doesn't.
    nonisolated static func name(of kind: String) -> String {
        kindNames[kind.lowercased()] ?? kind.prefix(1).uppercased() + kind.dropFirst()
    }

    /// The filters a list offers: All, a filter for each kind the lists give (the most common
    /// first), and Built from source when any firmware is.
    nonisolated static func scopes(for entries: [CatalogueEntry]) -> [FirmwareScope] {
        var scopes: [FirmwareScope] = [.all]
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
    /// Firmwares the lists give this kind, such as "synth".
    case kind(String)
    /// Firmwares built from their source by GitHub Actions, as a signed record says.
    case builtFromSource

    var name: String {
        switch self {
        case .all: "All"
        case .kind(let kind): FirmwareFilter.name(of: kind)
        case .builtFromSource: "Built from source"
        }
    }

    /// The filter as it's kept in the settings, e.g. "kind:synth".
    var storedValue: String {
        switch self {
        case .all: "all"
        case .kind(let kind): "kind:\(kind)"
        case .builtFromSource: "builtFromSource"
        }
    }

    init(storedValue: String?) {
        switch storedValue {
        case "builtFromSource": self = .builtFromSource
        case let value? where value.hasPrefix("kind:"): self = .kind(String(value.dropFirst("kind:".count)))
        default: self = .all
        }
    }

    /// This filter if `scopes` offers it, as a kind can drop out of the lists; otherwise All.
    func offered(in scopes: [Self]) -> Self {
        scopes.contains(self) ? self : .all
    }

    func includes(_ entry: CatalogueEntry) -> Bool {
        switch self {
        case .all: true
        case .kind(let kind): FirmwareFilter.isKind(kind, entry)
        case .builtFromSource: entry.isBuiltFromSource
        }
    }
}

/// The order a firmware list shows its firmwares in.
enum FirmwareOrder: String, CaseIterable, Identifiable {
    /// M-VAVE's firmware first, then by name.
    case name
    /// The newest release first, then by name; firmwares without a release date go last.
    case updated
    /// The most installs from The Firmware Hub's site first, then by name; firmwares the hub
    /// doesn't list have no count, so they go last.
    case installs

    /// Under Most installed, whose counts they are.
    static let installsSource = "Install counts are from The Firmware Hub's site."
    /// Under Most installed, above the firmwares with no count.
    static let uncountedNote = "These aren't on The Firmware Hub, so they have no install count."

    var id: String { rawValue }

    var name: String {
        switch self {
        case .name: "Name"
        case .updated: "Updated"
        case .installs: "Most installed"
        }
    }

    /// `entries`, as the catalogue gives them (by name), in this order.
    func sorted(_ entries: [CatalogueEntry]) -> [CatalogueEntry] {
        switch self {
        case .name:
            entries
        case .updated:
            // Dates are yyyy-mm-dd, so they sort as text; the index keeps the name order for a tie.
            entries.enumerated()
                .sorted { ($0.element.date ?? "", $1.offset) > ($1.element.date ?? "", $0.offset) }
                .map(\.element)
        case .installs:
            entries.enumerated()
                .sorted { ($0.element.installs ?? -1, $1.offset) > ($1.element.installs ?? -1, $0.offset) }
                .map(\.element)
        }
    }

    /// Under Most installed, the first of `sorted` with no install count, where the list says the
    /// rest aren't on The Firmware Hub; nil in the other orders.
    func firstUncounted(in sorted: [CatalogueEntry]) -> CatalogueEntry.ID? {
        guard self == .installs, sorted.contains(where: { $0.installs != nil }) else { return nil }
        return sorted.first { $0.installs == nil }?.id
    }
}
