import Foundation

/// The merged firmware list: saved on the phone, and published as fm-1.drewr.dev/firmwares.json.
public struct MergedCatalogue: Codable, Sendable, Equatable {
    /// The format this code writes and reads.
    ///
    /// It's raised only when a change would break an app that reads the list: a field removed,
    /// renamed or given another meaning. Added fields keep it, as readers ignore what they don't
    /// know. An app refuses a list with a format newer than it knows.
    public static let currentFormat = 1

    /// The list's format; nil in lists saved before it was recorded, which are format 1.
    public var formatVersion: Int?
    /// When the list was built.
    public var builtAt: Date
    /// When the firmware hub last rebuilt its catalogue, as the hub writes it, e.g. "2026-10-14 20:00 UTC".
    var hubUpdated: String?
    var entries: [CatalogueEntry]
    /// Sources that couldn't be read on this refresh, in plain words.
    public var problems: [String]

    /// How many firmwares the list has.
    public var count: Int { entries.count }

    /// Whether an app that knows formats up to ``currentFormat`` can read it.
    public var isReadable: Bool { (formatVersion ?? 1) <= Self.currentFormat }
}

/// Builds the merged list: the firmware hub's catalogue, plus the firmwares on fm1-editor.com and
/// in aroum's FM1 Resource Hub that it doesn't carry, with packages discovered for those where
/// possible.
public struct CatalogueBuilder: Sendable {
    typealias Fetch = PackageDiscovery.Fetch

    enum Failure: Error, LocalizedError {
        case nothingReachable

        var errorDescription: String? {
            "Couldn't reach the firmware hub, fm1-editor.com or aroum's FM1 Resource Hub."
        }
    }

    var hubURL = HubFeed.defaultURL
    var editorURL = EditorListing.defaultURL
    var resourceHubURL = ResourceHubListing.defaultURL
    let fetch: Fetch
    /// Whether to fill in missing descriptions from GitHub, at a request per firmware.
    let describesFromGitHub: Bool

    /// - Parameters:
    ///   - fetch: Downloads an address, throwing for anything but success.
    ///   - describesFromGitHub: Fill in missing descriptions from each project's GitHub
    ///     description. It takes a GitHub API request per firmware, so it's for fm1-catalogue,
    ///     which has a token, not the app.
    public init(fetch: @escaping @Sendable (URL) async throws -> Data, describesFromGitHub: Bool = false) {
        self.fetch = fetch
        self.describesFromGitHub = describesFromGitHub
    }

    /// Fetches the lists and merges them, falling back on `previous` for packages that can't be
    /// found this time.
    public func build(after previous: MergedCatalogue?) async throws -> MergedCatalogue {
        try await build(previous: previous?.entries ?? [])
    }

    /// Fetches the lists and merges them. `previous` supplies discovered packages to fall back
    /// on when a project's site or GitHub can't be reached this time.
    func build(previous: [CatalogueEntry] = []) async throws -> MergedCatalogue {
        async let hubData = try? fetch(hubURL)
        async let editorData = try? fetch(editorURL)
        async let resourceHubData = try? fetch(resourceHubURL)
        let hub = await hubData.flatMap { try? HubFeed.decode($0) }
        let editor = await editorData.flatMap { String(data: $0, encoding: .utf8) }
            .map { html in EditorListing(html: html, pageURL: editorURL) }
        let resourceHub = await resourceHubData.flatMap { String(data: $0, encoding: .utf8) }
            .map { markdown in ResourceHubListing(markdown: markdown) }

        var problems: [String] = []
        if hub == nil { problems.append("The firmware hub couldn't be read.") }
        if editor == nil || editor?.entries.isEmpty == true { problems.append("fm1-editor.com couldn't be read.") }
        if resourceHub == nil || resourceHub?.entries.isEmpty == true {
            problems.append("aroum's FM1 Resource Hub couldn't be read.")
        }
        guard hub != nil || editor?.entries.isEmpty == false || resourceHub?.entries.isEmpty == false else {
            throw Failure.nothingReachable
        }

        let merged = Self.merge(
            resourceHub: resourceHub?.entries ?? [],
            into: Self.merge(
                hub: hub?.entries(relativeTo: hubURL) ?? [], editor: editor?.entries ?? [], editorURL: editorURL)
        )
        let discovery = PackageDiscovery(fetch: fetch)
        let previousByID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let resolved = await withTaskGroup(of: (Int, CatalogueEntry).self) { group in
            for (index, entry) in merged.enumerated() where entry.packageURL == nil {
                group.addTask {
                    guard
                        let found = await discovery.discover(
                            name: entry.name, links: entry.links, isOfficial: entry.isOfficial)
                    else {
                        return (index, Self.fallBack(entry, to: previousByID[entry.id]))
                    }
                    return (index, Self.apply(found, to: entry))
                }
            }
            var entries = merged
            for await (index, entry) in group {
                entries[index] = entry
            }
            return entries
        }
        return MergedCatalogue(
            formatVersion: MergedCatalogue.currentFormat,
            builtAt: .now,
            hubUpdated: hub?.updated,
            entries: describesFromGitHub ? await describe(resolved, previous: previousByID) : resolved,
            problems: problems
        )
    }

    // MARK: - Descriptions.

    /// Fills in firmwares without a description from their GitHub repository's description,
    /// falling back on the previous list's when GitHub can't be reached.
    func describe(_ entries: [CatalogueEntry], previous: [String: CatalogueEntry]) async -> [CatalogueEntry] {
        let repos = entries.map(Self.describingRepo)
        let counts = repos.compactMap(\.self).reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return await withTaskGroup(of: (Int, String?).self) { group in
            for (index, entry) in entries.enumerated() where entry.what == nil {
                // A repository several firmwares share describes none of them in particular.
                guard let repo = repos[index], counts[repo] == 1 else { continue }
                group.addTask {
                    let url = URL(literal: "https://api.github.com/repos").appending(path: repo)
                    guard let data = try? await fetch(url) else {
                        let earlier = previous[entry.id]
                        return (index, earlier?.whatSource == .gitHub ? earlier?.what : nil)
                    }
                    return (index, try? JSONDecoder().decode(GitHubRepository.self, from: data).description)
                }
            }
            var described = entries
            for await (index, description) in group {
                guard let text = description?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
                else { continue }
                described[index].what = text
                described[index].whatSource = .gitHub
            }
            return described
        }
    }

    /// The GitHub repository whose description describes the firmware, as "owner/name".
    ///
    /// It's the listed repository, or the first github.com link. Not one inferred from a GitHub
    /// Pages site, which can be a shared page for several firmwares.
    static func describingRepo(of entry: CatalogueEntry) -> String? {
        if let repo = entry.repo { return repo.lowercased() }
        let gitHubLinks = entry.links.filter { $0.url.host()?.lowercased() == "github.com" }
        return PackageDiscovery.gitHubRepos(in: gitHubLinks).first.map { "\($0.owner)/\($0.name)".lowercased() }
    }

    // MARK: - Merging.

    /// Hub entries, enriched with what fm1-editor.com adds, then the editor's extra firmwares.
    static func merge(hub: [CatalogueEntry], editor: [EditorListing.Entry], editorURL: URL) -> [CatalogueEntry] {
        var entries = hub
        for listed in editor {
            var components = URLComponents(url: editorURL, resolvingAgainstBaseURL: true)
            components?.fragment = listed.anchor
            let pageLink = CatalogueLink(label: "fm1-editor.com listing", url: components?.url ?? editorURL)
            if let index = entries.firstIndex(where: { matches($0, listed) }) {
                var entry = entries[index]
                entry.listing.insert(.editor)
                if entry.what == nil { entry.what = listed.blurb }
                if entry.author == nil { entry.author = listed.author }
                if entry.stars == nil { entry.stars = listed.stars }
                for link in listed.links + [pageLink]
                where !entry.links.contains(where: { $0.comparable == link.comparable }) {
                    entry.links.append(link)
                }
                entries[index] = entry
            } else {
                let isOfficial = isOfficialV15(listed)
                let id = isOfficial ? "mvave-official" : "fm1-editor-\(listed.anchor)"
                // Each entry needs its own ID: two the same would show as a blank row.
                guard !entries.contains(where: { $0.id == id }) else { continue }
                entries.append(
                    CatalogueEntry(
                        id: id,
                        name: isOfficial ? "M-VAVE official firmware" : listed.name,
                        author: listed.author,
                        what: listed.blurb,
                        version: listed.latest,
                        date: listed.updated,
                        links: listed.links + [pageLink],
                        listing: .editor,
                        isOfficial: isOfficial,
                        stars: listed.stars
                    ))
            }
        }
        return entries
    }

    /// Adds aroum's FM1 Resource Hub: what it adds to firmwares already listed, then the rest.
    static func merge(resourceHub: [ResourceHubListing.Entry], into listed: [CatalogueEntry]) -> [CatalogueEntry] {
        var entries = listed
        let pageLink = CatalogueLink(label: "FM1 Resource Hub listing", url: ResourceHubListing.pageURL)
        // A repository several firmwares share (one repository for HYP-1, LOF-1, ECO-1 and GRAV-1)
        // doesn't say which firmware is which.
        let repoCounts = resourceHub.flatMap { Set(repos(in: $0.links)) }.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        let sharedRepos = Set(repoCounts.filter { $0.value > 1 }.keys)
        for found in resourceHub {
            let isSame = { (entry: CatalogueEntry) in
                matches(entry, links: found.links, name: found.name, ignoringRepos: sharedRepos)
            }
            if let index = entries.firstIndex(where: isSame) {
                var entry = entries[index]
                entry.listing.insert(.resourceHub)
                if entry.author == nil { entry.author = found.author }
                if entry.licence == nil { entry.licence = found.licence }
                for kind in found.kinds where !entry.kinds.contains(kind) {
                    entry.kinds.append(kind)
                }
                for link in found.links + [pageLink]
                where !entry.links.contains(where: { $0.comparable == link.comparable }) {
                    entry.links.append(link)
                }
                entries[index] = entry
            } else {
                let id = "resource-hub-\(slug(found.name))"
                // Each entry needs its own ID: two the same would show as a blank row.
                guard !entries.contains(where: { $0.id == id }) else { continue }
                entries.append(
                    CatalogueEntry(
                        id: id,
                        name: found.name,
                        author: found.author,
                        kinds: found.kinds,
                        links: found.links + [pageLink],
                        listing: .resourceHub,
                        licence: found.licence
                    ))
            }
        }
        return entries
    }

    /// A name as an ID: lowercase letters and numbers, joined by hyphens.
    static func slug(_ name: String) -> String {
        name.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) || !$0.isASCII })
            .joined(separator: "-")
    }

    /// Whether an editor listing is M-VAVE's V15: the "stock" entry, or one linking to m-vave.com.
    ///
    /// M-VAVE's open-source firmware (FM1 Open) links there too, but isn't V15, so it's listed as
    /// a firmware of its own.
    static func isOfficialV15(_ listed: EditorListing.Entry) -> Bool {
        if listed.anchor == "stock" { return true }
        let isOpen = [listed.anchor, listed.name].contains { $0.localizedCaseInsensitiveContains("open") }
        return !isOpen && listed.links.contains { $0.url.host()?.contains("m-vave.com") == true }
    }

    /// The same firmware: a shared GitHub repository, or the same name once punctuation is ignored.
    static func matches(_ entry: CatalogueEntry, _ listed: EditorListing.Entry) -> Bool {
        sharesRepo(entry, listed.links) || normalisedName(entry.name) == normalisedName(listed.name)
    }

    /// The same firmware as one in another list: a shared GitHub repository (other than
    /// `ignoringRepos`), the same name once punctuation is ignored, or a shared project site when
    /// the names start the same way.
    ///
    /// A name matches any of its " / " alternatives, as "FANTASMA / Pelucco" does Fantasma. A site
    /// matches a page under it, as baudgirl.com does baudgirl.com/work/FM-1+VA. A site alone isn't
    /// enough, as one can host several firmwares: designburgapps.com has OberVave and FM-1 Doom.
    static func matches(
        _ entry: CatalogueEntry, links: [CatalogueLink], name: String, ignoringRepos: Set<String> = []
    ) -> Bool {
        let theirRepos = Set(repos(in: links)).subtracting(ignoringRepos)
        if !theirRepos.isDisjoint(with: repos(of: entry)) { return true }
        let names = name.components(separatedBy: " / ")
        if names.map(normalisedName).contains(normalisedName(entry.name)) { return true }
        guard names.contains(where: { firstWord($0) == firstWord(entry.name) }) else { return false }
        let ours = entry.links.filter(isProjectSite).map(\.comparable)
        let theirs = links.filter(isProjectSite).map(\.comparable)
        return ours.contains { site in theirs.contains { isSameSite(site, $0) } }
    }

    /// A name's first word, in lowercase letters and numbers, e.g. "baud" for "Baud Girl (FM-1+VA)".
    private static func firstWord(_ name: String) -> String {
        normalisedName(name.split(separator: " ").first.map(String.init) ?? "")
    }

    /// The same address, or one a page under the other.
    ///
    /// Not across a GitHub Pages host, which one person's projects share.
    private static func isSameSite(_ first: String, _ second: String) -> Bool {
        if first == second { return true }
        let (shorter, longer) = first.count < second.count ? (first, second) : (second, first)
        return !shorter.hasSuffix("github.io") && longer.hasPrefix(shorter + "/")
    }

    private static func sharesRepo(_ entry: CatalogueEntry, _ links: [CatalogueLink]) -> Bool {
        !Set(repos(in: links)).isDisjoint(with: repos(of: entry))
    }

    /// The GitHub repositories an entry links to, or names, as "owner/name" in lowercase.
    private static func repos(of entry: CatalogueEntry) -> Set<String> {
        var links = entry.links
        if let repo = entry.repo, let url = URL(string: "https://github.com/\(repo)") {
            links.append(CatalogueLink(label: "", url: url))
        }
        return Set(repos(in: links))
    }

    /// The GitHub repositories links point at, including through GitHub Pages, as "owner/name".
    private static func repos(in links: [CatalogueLink]) -> [String] {
        PackageDiscovery.gitHubRepos(in: links).map { "\($0.owner)/\($0.name)".lowercased() }
    }

    /// A link that identifies one project: not GitHub (matched by repository instead), nor a
    /// community or video site that hosts many.
    private static func isProjectSite(_ link: CatalogueLink) -> Bool {
        guard let host = link.url.host()?.lowercased() else { return false }
        let shared = [
            "github.com", "reddit.com", "youtube.com", "youtu.be", "discord.gg", "discord.com", "instagram.com",
            "fm1-editor.com", "thefirmwarehub.com",
        ]
        return !shared.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func normalisedName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func apply(_ found: DiscoveredPackage, to entry: CatalogueEntry) -> CatalogueEntry {
        var entry = entry
        entry.packageURL = found.url
        entry.packageOrigin = found.origin
        entry.version = found.version.map(ReleaseVersion.asListed) ?? entry.version
        entry.date = found.date ?? entry.date
        entry.beta = entry.beta || found.beta
        entry.product = found.product
        entry.size = found.size
        entry.sha256 = found.sha256
        entry.builds = found.builds
        entry.build = nil
        entry.releaseURL = found.releaseURL ?? entry.releaseURL
        return entry
    }

    /// Keeps the package found on an earlier refresh when discovery fails this time.
    static func fallBack(_ entry: CatalogueEntry, to previous: CatalogueEntry?) -> CatalogueEntry {
        // A firmware that isn't M-VAVE's official one never keeps their package, as an earlier list
        // could give it to their open firmware.
        guard let previous, previous.packageURL != nil, entry.isOfficial || previous.packageOrigin != .mvave
        else {
            return entry
        }
        var entry = entry
        entry.packageURL = previous.packageURL
        entry.packageOrigin = previous.packageOrigin
        entry.version = previous.version
        entry.date = previous.date
        entry.beta = previous.beta
        entry.product = previous.product
        entry.size = previous.size
        entry.sha256 = previous.sha256
        return entry
    }
}
