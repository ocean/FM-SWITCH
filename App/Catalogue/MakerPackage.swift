import FM1Kit
import Foundation

/// Where the maker of a firmware The Firmware Hub lists publishes the package the hub lists.
///
/// The hub's terms for apps that use its list ask for packages to come from the makers, not from
/// its mirror (thefirmwarehub.com/kb/, "Using the hub's firmware list"). The hub's package is
/// found by its SHA-256: among the project's GitHub release files, then among the `.fwsc` files
/// kept in its repository, pinned to the commit they were found at so the file can't change under
/// the list, then on the project's GitHub Pages site. Firmwares the hub builds itself have none
/// of these, and are listed with links only.
struct MakerPackage: Sendable {
    let fetch: PackageDiscovery.Fetch
    /// Reads the `.fwsc` files on a Pages site built by a workflow, when it can.
    var pagesFiles: PagesFiles?

    /// Where to download the hub's package for `entry`, or nil when its maker doesn't publish it.
    func find(for entry: CatalogueEntry) async -> (url: URL, origin: CatalogueEntry.PackageOrigin)? {
        guard let repo = entry.repo, let sha256 = entry.sha256?.lowercased() else { return nil }
        if let url = await releaseFile(repo: repo, sha256: sha256, size: entry.size) {
            return (url, .githubRelease)
        }
        if let url = await repositoryFile(repo: repo, sha256: sha256, size: entry.size) {
            return (url, .projectPage)
        }
        if let url = await pagesFile(repo: repo, sha256: sha256, size: entry.size) {
            return (url, .projectPage)
        }
        return nil
    }

    /// A release file with this checksum, as GitHub states it or, for files uploaded before
    /// GitHub stated checksums, as the file of the same size reads.
    func releaseFile(repo: String, sha256: String, size: Int?) async -> URL? {
        let url = Self.api.appending(path: "repos/\(repo)/releases")
            .appending(queryItems: [URLQueryItem(name: "per_page", value: "30")])
        guard let data = try? await fetch(url),
            let releases = try? JSONDecoder().decode([GitHubRelease].self, from: data)
        else { return nil }
        let builds = releases.flatMap(PackageDiscovery.builds(of:))
        if let stated = builds.first(where: { $0.sha256?.lowercased() == sha256 }) { return stated.url }
        for build in builds where build.sha256 == nil && size != nil && build.size == size {
            if await reads(build.url, as: sha256) { return build.url }
        }
        return nil
    }

    /// A `.fwsc` file in the repository with this checksum, at the newest commit of `ref`, in the
    /// folder `folder` or below.
    func repositoryFile(repo: String, ref: String = "HEAD", folder: String = "", sha256: String, size: Int?) async
        -> URL?
    {
        guard let data = try? await fetch(Self.api.appending(path: "repos/\(repo)/commits/\(ref)")),
            let commit = try? JSONDecoder().decode(GitHubCommit.self, from: data).sha,
            let data = try? await fetch(
                Self.api.appending(path: "repos/\(repo)/git/trees/\(commit)")
                    .appending(queryItems: [URLQueryItem(name: "recursive", value: "1")])),
            let tree = try? JSONDecoder().decode(GitHubTree.self, from: data)
        else { return nil }
        let files = tree.tree.filter { file in
            file.type == "blob" && file.path.hasPrefix(folder) && file.path.lowercased().hasSuffix(".fwsc")
                && (size == nil || file.size == size)
        }
        for file in files {
            let url = URL(literal: "https://raw.githubusercontent.com").appending(
                path: "\(repo)/\(commit)/\(file.path)")
            if await reads(url, as: sha256) { return url }
        }
        return nil
    }

    /// A `.fwsc` file with this checksum on the project's GitHub Pages site: in the branch a site
    /// built from a branch serves, pinned to its commit, or among the files on a site built by a
    /// workflow, at its address on the site.
    func pagesFile(repo: String, sha256: String, size: Int?) async -> URL? {
        guard let data = try? await fetch(Self.api.appending(path: "repos/\(repo)/pages")),
            let pages = try? JSONDecoder().decode(GitHubPages.self, from: data),
            let site = URL(string: pages.htmlURL)
        else { return nil }
        if pages.buildType == "workflow" {
            guard let pagesFiles else { return nil }
            let files = await pagesFiles(repo, site)
            return files.first { file in
                (size == nil || file.contents.count == size) && FwscPackage.sha256Hex(file.contents) == sha256
            }?.url
        }
        guard let source = pages.source else { return nil }
        let folder = source.path.trimmingPrefix("/")
        return await repositoryFile(
            repo: repo, ref: source.branch, folder: folder.isEmpty ? "" : "\(folder)/", sha256: sha256, size: size)
    }

    /// Whether the file at `url` has this checksum.
    private func reads(_ url: URL, as sha256: String) async -> Bool {
        guard let data = try? await fetch(url) else { return false }
        return FwscPackage.sha256Hex(data) == sha256
    }

    private static let api = URL(literal: "https://api.github.com")
}

/// Reads the `.fwsc` files on a GitHub Pages site built by a workflow.
///
/// It's given the repository and the site's address, and gives each file's address on the site
/// with its contents. Such a site's files aren't in its repository, and reading them downloads a
/// lot, so only fm1-catalogue does it.
public typealias PagesFiles = @Sendable (_ repo: String, _ site: URL) async -> [PagesFile]

/// A file on a GitHub Pages site.
public struct PagesFile: Sendable {
    /// The file's address on the site.
    public var url: URL
    /// The file.
    public var contents: Data

    /// A file at `url` on a site, holding `contents`.
    public init(url: URL, contents: Data) {
        self.url = url
        self.contents = contents
    }
}

/// A repository's GitHub Pages site, as GitHub's REST API describes it.
private struct GitHubPages: Decodable {
    struct Source: Decodable {
        var branch: String
        var path: String
    }

    var htmlURL: String
    var buildType: String?
    var source: Source?

    enum CodingKeys: String, CodingKey {
        case htmlURL = "html_url"
        case buildType = "build_type"
        case source
    }
}

/// A commit as GitHub's REST API gives it, with only its hash.
private struct GitHubCommit: Decodable {
    var sha: String
}

/// A repository's files at a commit, as GitHub's REST API lists them.
private struct GitHubTree: Decodable {
    struct File: Decodable {
        var path: String
        var type: String
        var size: Int?
    }

    var tree: [File]
}
