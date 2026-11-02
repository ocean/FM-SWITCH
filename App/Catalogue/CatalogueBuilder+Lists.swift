/// Merging the lists without packages into the list, and keeping the firmwares of lists that
/// can't be read.
extension CatalogueBuilder {
    /// Adds aroum's FM1 Resource Hub: what it adds to firmwares already listed, then the rest.
    static func merge(resourceHub: [ListedFirmware], into listed: [CatalogueEntry]) -> [CatalogueEntry] {
        merge(
            resourceHub,
            as: .resourceHub,
            idPrefix: "resource-hub",
            pageLink: CatalogueLink(label: "FM1 Resource Hub listing", url: ResourceHubListing.pageURL),
            into: listed)
    }

    /// Adds mutant.cloud: what it adds to firmwares already listed, then the rest.
    static func merge(mutantCloud: [ListedFirmware], into listed: [CatalogueEntry]) -> [CatalogueEntry] {
        merge(
            mutantCloud,
            as: .mutantCloud,
            idPrefix: "mutant-cloud",
            pageLink: CatalogueLink(label: "mutant.cloud listing", url: MutantCloudListing.pageURL),
            into: listed)
    }

    /// Adds a list without packages: what it adds to firmwares already listed, then the rest,
    /// each linking to its page on the list, or else to `pageLink`.
    static func merge(
        _ found: [ListedFirmware],
        as listing: CatalogueEntry.Listing,
        idPrefix: String,
        pageLink: CatalogueLink,
        into listed: [CatalogueEntry]
    ) -> [CatalogueEntry] {
        var entries = listed
        // A repository several firmwares share (one repository for HYP-1, LOF-1, ECO-1 and GRAV-1)
        // doesn't say which firmware is which.
        let repoCounts = found.flatMap { Set(repos(in: $0.links)) }.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        let sharedRepos = Set(repoCounts.filter { $0.value > 1 }.keys)
        for firmware in found {
            let page = firmware.page.map { CatalogueLink(label: pageLink.label, url: $0) } ?? pageLink
            let isSame = { (entry: CatalogueEntry) in
                matches(entry, links: firmware.links, name: firmware.name, ignoringRepos: sharedRepos)
            }
            if let index = entries.firstIndex(where: isSame) {
                var entry = entries[index]
                entry.listing.insert(listing)
                if entry.author == nil { entry.author = firmware.author }
                if entry.licence == nil { entry.licence = firmware.licence }
                for kind in firmware.kinds where !entry.kinds.contains(kind) {
                    entry.kinds.append(kind)
                }
                for link in firmware.links + [page]
                where !entry.links.contains(where: { $0.comparable == link.comparable }) {
                    entry.links.append(link)
                }
                entries[index] = entry
            } else {
                let id = "\(idPrefix)-\(slug(firmware.listID ?? firmware.name))"
                // Each entry needs its own ID: two the same would show as a blank row.
                guard !entries.contains(where: { $0.id == id }) else { continue }
                entries.append(
                    CatalogueEntry(
                        id: id,
                        name: firmware.name,
                        author: firmware.author,
                        kinds: firmware.kinds,
                        links: firmware.links + [page],
                        listing: listing,
                        licence: firmware.licence
                    ))
            }
        }
        return entries
    }

    /// Keeps what `previous` had from lists that couldn't be read this time: the firmwares only
    /// they listed, unchanged, and their place in the listing of firmwares other lists still have.
    static func carry(
        _ previous: [CatalogueEntry], listedOnlyBy unread: CatalogueEntry.Listing, into fresh: [CatalogueEntry]
    ) -> [CatalogueEntry] {
        guard !unread.isEmpty else { return fresh }
        var entries = fresh
        for earlier in previous where !earlier.listing.isDisjoint(with: unread) {
            let kept = earlier.listing.intersection(unread)
            let index =
                entries.firstIndex { $0.id == earlier.id }
                ?? entries.firstIndex { matches($0, links: earlier.links, name: earlier.name) }
            if let index {
                entries[index].listing.formUnion(kept)
            } else if earlier.listing.isSubset(of: unread) {
                entries.append(earlier)
            }
        }
        return entries
    }
}
