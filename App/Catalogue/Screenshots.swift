import Foundation
import ImageIO

/// A picture of a firmware, and what opens to show it larger.
struct Screenshot: Hashable, Sendable {
    /// The picture, which may be one kept inside an SVG drawing, as a `data:` address.
    var image: URL
    /// The picture itself, or the drawing it's kept in, as a page that shows it.
    var page: URL
}

/// Finds the pictures in a firmware project's README, by reading the images it shows.
///
/// Nothing is kept in the app: the pictures are whatever the project's README shows today, so they
/// change as its author updates it. Badges, logos and icons aren't pictures of the firmware, so
/// they're left out. SVG drawings can't be shown, but some keep screen grabs inside them, which can.
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
    static func find(repo: String, fetch: (URL) async throws -> Data) async -> [Screenshot] {
        for readme in readmeAddresses(repo: repo) {
            guard let data = try? await fetch(readme), let text = String(bytes: data, encoding: .utf8) else { continue }
            var found: [Screenshot] = []
            var seen = Set<URL>()
            for picture in pictures(in: text, readme: readme) where found.count < limit {
                guard isDrawing(picture) else {
                    found.append(Screenshot(image: picture, page: picture))
                    continue
                }
                guard let drawing = try? await fetch(picture), let text = String(bytes: drawing, encoding: .utf8) else {
                    continue
                }
                // The same screen grab can be in more than one drawing.
                for image in images(inDrawing: text) where seen.insert(image).inserted {
                    found.append(Screenshot(image: image, page: page(showing: picture)))
                }
            }
            return Array(found.prefix(limit))
        }
        return []
    }

    /// The pictures kept inside an SVG drawing, as `data:` addresses, in the order it draws them.
    ///
    /// Small ones are left out, as they're icons rather than screens.
    static func images(inDrawing svg: String) -> [URL] {
        let pattern = #"href\s*=\s*["']\s*(data:image/(?:png|jpeg|gif|webp);base64,[^"']+)["']"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return expression.matches(in: svg, range: NSRange(svg.startIndex..., in: svg)).compactMap { match in
            guard let found = Range(match.range(at: 1), in: svg) else { return nil }
            // Base64 in a drawing can be split over lines.
            let address = svg[found].filter { !$0.isWhitespace }
            guard let comma = address.firstIndex(of: ","),
                let data = Data(base64Encoded: String(address[address.index(after: comma)...])),
                isScreenSized(data)
            else { return nil }
            return URL(string: address)
        }
    }

    /// Whether an image is big enough to be a screen grab: the FM-1's screen is 240 pixels square.
    private static func isScreenSized(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        return min(width, height) >= 100
    }

    private static func isDrawing(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "svg"
    }

    /// A page that shows a drawing, as GitHub's file server gives drawings as text.
    private static func page(showing drawing: URL) -> URL {
        let parts = drawing.pathComponents
        guard drawing.host() == "raw.githubusercontent.com", parts.count > 4 else { return drawing }
        let path = ([parts[1], parts[2], "blob"] + parts[3...]).joined(separator: "/")
        return URL(string: "https://github.com/\(path)") ?? drawing
    }

    /// The pictures and drawings a README shows, as markdown `![alt](address)` or HTML `<img src="address">`.
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

    /// Whether `url` looks like a picture of the firmware: a photo, a screen grab or a drawing that
    /// may hold some, or an image attached on GitHub, and not a badge, logo or icon.
    private static func isPicture(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        let badgeHosts = ["img.shields.io", "badgen.net", "badge.fury.io"]
        if badgeHosts.contains(where: host.hasPrefix) { return false }
        let name = url.lastPathComponent.lowercased()
        let decorations = ["logo", "icon", "badge", "shield", "avatar"]
        if decorations.contains(where: name.contains) { return false }
        // Images attached to a README on GitHub have no extension.
        if host == "github.com", url.path().hasPrefix("/user-attachments/assets/") { return true }
        return ["png", "jpg", "jpeg", "gif", "webp", "svg"].contains(url.pathExtension.lowercased())
    }
}
