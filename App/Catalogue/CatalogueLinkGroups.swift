import Foundation

extension CatalogueLink {
    /// The links worth showing up front, in the order they're shown.
    enum Kind: CaseIterable {
        case projectSite
        case sourceCode
        case manual
    }

    /// Which up-front link this is, judged by its label, or `nil` for any other link.
    var kind: Kind? {
        switch label.lowercased() {
        case "project site": .projectSite
        case "source code", "source", "repository": .sourceCode
        case "manual": .manual
        default: nil
        }
    }

    /// The label as shown, with the lists' vaguer names made clearer.
    var displayLabel: String {
        label.caseInsensitiveCompare("Install") == .orderedSame ? "Web installer" : label
    }
}

extension CatalogueEntry {
    /// The lists' links, then the signed build's run on GitHub Actions, for a firmware built from
    /// its source.
    var pageLinks: [CatalogueLink] {
        guard isBuiltFromSource, let build = sourceBuild, let url = build.run ?? build.commitURL else { return links }
        return links + [CatalogueLink(label: "Signed build of commit \(build.shortCommit)", url: url)]
    }

    /// The project site, source code and manual, where the firmware has them: one link of each.
    var mainLinks: [CatalogueLink] {
        CatalogueLink.Kind.allCases.compactMap { kind in
            links.first { $0.kind == kind }
        }
    }

    /// Every other link, in the order the lists give them.
    var moreLinks: [CatalogueLink] {
        let main = mainLinks
        return pageLinks.filter { !main.contains($0) }
    }
}
