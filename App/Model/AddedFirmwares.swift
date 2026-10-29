import Foundation

extension CatalogueEntry {
    /// The start of the ID of a firmware added from a file that no list describes.
    static let addedFromFilePrefix = "file-"

    /// Whether it's a firmware added from a file that no list describes.
    var isFromFile: Bool { id.hasPrefix(Self.addedFromFilePrefix) }

    /// A firmware added from a file that no list describes, as an entry like the listed ones, so
    /// it shows in My firmwares and installs from its page.
    init(addedFrom item: StoredFirmware) {
        self.init(
            id: Self.addedFromFilePrefix + item.sha256,
            name: item.name,
            author: item.author,
            version: item.version,
            product: item.product,
            size: item.size,
            sha256: item.sha256,
            listing: [])
    }
}

extension AppModel {
    /// Firmwares added from files that no list describes, by name.
    var addedFromFiles: [CatalogueEntry] {
        let listed = Set(catalogue.entries.compactMap(\.sha256))
        return library.items
            .filter { $0.source == .imported && !listed.contains($0.sha256) }
            .map(CatalogueEntry.init(addedFrom:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The firmware with this ID, listed or added from a file.
    func firmware(id: String) -> CatalogueEntry? {
        catalogue.entry(id: id) ?? addedFromFiles.first { $0.id == id }
    }
}
