import FM1Catalogue
import Foundation

/// The `.fwsc` files on a GitHub Pages site built by a workflow, whose files are built in the
/// workflow, not kept in the repository.
///
/// They're read from the last deploy's `github-pages` artifact, a zip holding a tar of the whole
/// site, when GitHub still keeps it and it's under 300 MB; that needs GITHUB_TOKEN. Otherwise
/// they're the files the site's own pages link to.
///
/// - Parameters:
///   - repo: The repository, such as "juanjiant-bit/JIANT".
///   - site: The site's address.
/// - Returns: The files, or none when none can be read.
@Sendable
func pagesFiles(repo: String, site: URL) async -> [PagesFile] {
    let deployed = await deployedFiles(repo: repo, site: site)
    return deployed.isEmpty ? await linkedFiles(site: site) : deployed
}

/// The `.fwsc` files in the last deploy's `github-pages` artifact, each at its address on the site.
private func deployedFiles(repo: String, site: URL) async -> [PagesFile] {
    guard let list = URL(string: "https://api.github.com/repos/\(repo)/actions/artifacts?name=github-pages&per_page=1"),
        let data = try? await fetch(list),
        let artifact = try? JSONDecoder().decode(Artifacts.self, from: data).artifacts.first,
        !artifact.expired, artifact.size <= 300_000_000,
        let zip = try? await downloadArtifact(artifact.download)
    else { return [] }
    let folder = FileManager.default.temporaryDirectory.appending(path: "fm1-pages-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let siteFolder = folder.appending(path: "site")
    do {
        try FileManager.default.createDirectory(at: siteFolder, withIntermediateDirectories: true)
        try zip.write(to: folder.appending(path: "artifact.zip"))
        try run("/usr/bin/ditto", "-x", "-k", folder.appending(path: "artifact.zip").path(), folder.path())
        try run("/usr/bin/tar", "-xf", folder.appending(path: "artifact.tar").path(), "-C", siteFolder.path())
    } catch {
        return []
    }
    return fwscFiles(in: siteFolder, site: site)
}

/// The `.fwsc` files on the site that its home page, or a page or script the home page links to,
/// names: an installer page names the file it sends.
private func linkedFiles(site: URL) async -> [PagesFile] {
    guard let home = try? await fetch(site) else { return [] }
    let pages = references(in: home, from: site, matching: ##"(?:href|src)="([^"#?]+(?:/|\.html|\.js))""##)
        .filter { $0.absoluteString.hasPrefix(site.absoluteString) }
    var named = references(in: home, from: site, matching: URL.fwscName)
    for page in pages.prefix(40) {
        guard let text = try? await fetch(page) else { continue }
        named.formUnion(references(in: text, from: page, matching: URL.fwscName))
    }
    var found: [PagesFile] = []
    for url in named.filter({ $0.absoluteString.hasPrefix(site.absoluteString) }).prefix(30) {
        if let contents = try? await fetch(url) {
            found.append(PagesFile(url: url, contents: contents))
        }
    }
    return found
}
/// The `.fwsc` files in an unpacked site, each at its address on the site.
private func fwscFiles(in folder: URL, site: URL) -> [PagesFile] {
    guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
    let root = folder.standardizedFileURL.path()
    var found: [PagesFile] = []
    for case let file as URL in files where file.pathExtension.lowercased() == "fwsc" {
        let path = file.standardizedFileURL.path().dropFirst(root.count)
        guard let contents = try? Data(contentsOf: file) else { continue }
        found.append(PagesFile(url: site.appending(path: String(path)), contents: contents))
    }
    return found
}

/// GitHub's list of a repository's artifacts.
private struct Artifacts: Decodable {
    struct Artifact: Decodable {
        var size: Int
        var expired: Bool
        var download: URL

        enum CodingKeys: String, CodingKey {
            case size = "size_in_bytes"
            case expired
            case download = "archive_download_url"
        }
    }

    var artifacts: [Artifact]
}

/// Downloads an artifact: GitHub's API answers with a redirect to storage that refuses the
/// GitHub token, so the redirect is followed without it.
private func downloadArtifact(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue("fm1-catalogue (+https://github.com/ocean/FM-SWITCH)", forHTTPHeaderField: "User-Agent")
    if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let (_, response) = try await URLSession.shared.data(for: request, delegate: StopsRedirects())
    guard let http = response as? HTTPURLResponse, (300..<400).contains(http.statusCode),
        let location = http.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:))
    else { throw URLError(.badServerResponse) }
    let (data, stored) = try await URLSession.shared.data(from: location)
    guard let stored = stored as? HTTPURLResponse, (200..<300).contains(stored.statusCode) else {
        throw URLError(.badServerResponse)
    }
    return data
}

/// Hands a redirect back instead of following it.
private final class StopsRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

/// Runs a tool, throwing when it fails.
private func run(_ tool: String, _ arguments: String...) throws {
    let process = Process()
    process.executableURL = URL(filePath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
}

extension URL {
    /// A `.fwsc` file's name or relative path, as a page or script writes it.
    fileprivate static let fwscName = #"([A-Za-z0-9_./-]+\.fwsc)\b"#
}

/// The addresses that the first group of `pattern` finds in a page, resolved against the page.
private func references(in data: Data, from page: URL, matching pattern: String) -> Set<URL> {
    guard let text = String(data: data, encoding: .utf8), let regex = try? NSRegularExpression(pattern: pattern) else {
        return []
    }
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    return Set(
        matches.compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { URL(string: String(text[$0]), relativeTo: page)?.absoluteURL }
        })
}
