extension CatalogueBuilder {
    /// The hub's firmwares, each pointing at the package it lists where its maker publishes it.
    ///
    /// One whose maker doesn't publish it keeps the address found on an earlier refresh for the
    /// same package, or else lists no package: still marked as the hub's, so nothing else is
    /// found for it in its place.
    func fromMakers(_ entries: [CatalogueEntry], previous: [CatalogueEntry]) async -> [CatalogueEntry] {
        let makers = MakerPackage(fetch: fetch, pagesFiles: pagesFiles)
        let previousByID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return await withTaskGroup(of: (Int, CatalogueEntry).self) { group in
            for (index, entry) in entries.enumerated() {
                group.addTask {
                    var entry = entry
                    if let found = await makers.find(for: entry) {
                        entry.packageURL = found.url
                        entry.packageOrigin = found.origin
                    } else if let earlier = previousByID[entry.id], earlier.packageURL != nil,
                        earlier.packageOrigin != .hub, earlier.sha256 == entry.sha256
                    {
                        entry.packageURL = earlier.packageURL
                        entry.packageOrigin = earlier.packageOrigin
                    } else {
                        entry.packageURL = nil
                    }
                    return (index, entry)
                }
            }
            var resolved = entries
            for await (index, entry) in group {
                resolved[index] = entry
            }
            return resolved
        }
    }
}
