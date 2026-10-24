import Foundation

/// Finds the pictures in a firmware project's README, by reading the images it shows.
///
/// Nothing is kept in the app: the pictures are whatever the project's README shows today, so they
/// change as its author updates it. Badges, logos and icons aren't pictures of the firmware, so
/// they're left out, as are SVGs, which can't be shown.
enum Screenshots {
    /// Up to this many pictures, in the order the README shows them.
    static let limit = 8

    /// Where a repository's README might be, in the order they're tried: GitHub's own file server
    /// under either usual name, then jsDelivr's copy, in case GitHub's file server can't be reached.
    static func readmeAddresses(repo: String) -> [URL] {
        [
            "https://raw.githubusercontent.com/\(repo)/HEAD/README.md",
            "https://raw.githubusercontent.com/\(repo)/HEAD/readme.md",
            "https://cdn.jsdelivr.net/gh/\(repo)@HEAD/README.md",
        ].compactMap(URL.init(string:))
    }

    /// The pictures in the README of `repo`, such as "zvenson/zp12", if it can be read.
    static func find(repo: String, fetch: (URL) async throws -> Data) async -> [URL] {
        for readme in readmeAddresses(repo: repo) {
            guard let data = try? await fetch(readme), let text = String(bytes: data, encoding: .utf8) else { continue }
            return Array(pictures(in: text, readme: readme).prefix(limit))
        }
        return []
    }

    /// The pictures a README shows, as markdown `![alt](address)` or HTML `<img src="address">`.
    ///
    /// Relative addresses are taken from where the README was read, and pictures on GitHub's
    /// pages are taken from its file server, so they load as images.
    static func pictures(in readme: String, readme address: URL) -> [URL] {
        let pattern = #"!\[[^\]]*\]\(\s*<?([^)\s>]+)|<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        var seen = Set<URL>()
        return expression.matches(in: readme, range: NSRange(readme.startIndex..., in: readme)).compactMap { match in
            let found = [1, 2].lazy.compactMap { Range(match.range(at: $0), in: readme) }.first
            guard let found,
                let url = URL(string: fromRepositoryRoot(String(readme[found])), relativeTo: address)?.absoluteURL,
                let picture = loadable(url), isPicture(picture), seen.insert(picture).inserted
            else { return nil }
            return picture
        }
    }

    /// A path from the top of the repository, as GitHub reads one starting with a slash.
    ///
    /// The README is at the top, so it's made relative to it.
    private static func fromRepositoryRoot(_ address: String) -> String {
        address.hasPrefix("/") && !address.hasPrefix("//") ? String(address.dropFirst()) : address
    }

    /// `url` as an address that gives the image itself: a file on a GitHub page is asked for raw.
    private static func loadable(_ url: URL) -> URL? {
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        let parts = url.pathComponents
        if url.host() == "github.com", parts.count > 4, parts[3] == "blob" || parts[3] == "raw",
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            components.queryItems = [URLQueryItem(name: "raw", value: "true")]
            return components.url
        }
        return url
    }

    /// Whether `url` looks like a picture of the firmware: a photo or screen grab, or an image
    /// attached on GitHub, and not a badge, logo or icon.
    private static func isPicture(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        let badgeHosts = ["img.shields.io", "badgen.net", "badge.fury.io"]
        if badgeHosts.contains(where: host.hasPrefix) { return false }
        let name = url.lastPathComponent.lowercased()
        let decorations = ["logo", "icon", "badge", "shield", "avatar"]
        if decorations.contains(where: name.contains) { return false }
        // Images attached to a README on GitHub have no extension.
        if host == "github.com", url.path().hasPrefix("/user-attachments/assets/") { return true }
        return ["png", "jpg", "jpeg", "gif", "webp"].contains(url.pathExtension.lowercased())
    }
}
