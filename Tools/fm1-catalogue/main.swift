import FM1Catalogue
import Foundation

// Builds the merged firmware list and writes it as JSON:
//
//     swift run -c release fm1-catalogue --output firmwares.json [--previous firmwares.json]
//
// --previous is the list published last time. Packages that can't be found this time fall back
// on it, as do the firmwares of a source that can't be read, and the new list is refused if it's
// much shorter. Firmwares no list describes get their
// GitHub repository's description. Set GITHUB_TOKEN to raise GitHub's API limit from 60 requests an
// hour to 1000 or more.
//
// Exit codes:
//   0  written
//   1  bad arguments, or the list couldn't be built or written
//   2  a source couldn't be read and there's no previous list to keep its firmwares from, so
//      nothing was written
//   3  the list is much shorter than the previous one, so nothing was written
//   4  written, but incomplete: a source couldn't be read, so its firmwares are from the previous
//      list. Publish it, and still fail the run so someone looks at why.

/// Why the tool stopped, with its exit code.
struct Stop: Error {
    var code: Int32
    var message: String
}

/// The command line's options.
struct Options {
    var output: URL
    var previous: URL?

    init(_ arguments: [String]) throws {
        var output: URL?
        var previous: URL?
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            guard let value = remaining.popFirst() else {
                throw Stop(code: 1, message: "\(argument) needs a path.")
            }
            switch argument {
            case "--output": output = URL(filePath: value)
            case "--previous": previous = URL(filePath: value)
            default: throw Stop(code: 1, message: "Unknown option \(argument).")
            }
        }
        guard let output else {
            throw Stop(code: 1, message: "Usage: fm1-catalogue --output <file> [--previous <file>]")
        }
        self.output = output
        self.previous = previous
    }
}

/// GETs an address, with the GitHub token for GitHub's API when one is set.
@Sendable
func fetch(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 30
    request.setValue("fm1-catalogue (+https://github.com/ocean/FM-SWITCH)", forHTTPHeaderField: "User-Agent")
    if url.host() == "api.github.com", let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"],
        !token.isEmpty
    {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLErrorKey: url, "status": http.statusCode])
    }
    return data
}

/// The list published last time, if there is one to read.
func readPrevious(_ url: URL?) throws -> MergedCatalogue? {
    guard let url, FileManager.default.fileExists(atPath: url.path()) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
        return try decoder.decode(MergedCatalogue.self, from: Data(contentsOf: url))
    } catch {
        throw Stop(code: 1, message: "Couldn't read the previous list: \(error.localizedDescription)")
    }
}

func run() async throws {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    let previous = try readPrevious(options.previous)
    let start = ContinuousClock.now

    let catalogue: MergedCatalogue
    do {
        catalogue = try await CatalogueBuilder(fetch: fetch, describesFromGitHub: true).build(after: previous)
    } catch {
        throw Stop(code: 2, message: error.localizedDescription)
    }
    if !catalogue.problems.isEmpty, previous == nil {
        throw Stop(code: 2, message: catalogue.problems.joined(separator: " "))
    }
    // A list that shrank by more than a fifth more likely lost a source's layout than its firmwares.
    if let previous, catalogue.count * 5 < previous.count * 4 {
        throw Stop(code: 3, message: "Only \(catalogue.count) firmwares, down from \(previous.count).")
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
        try encoder.encode(catalogue).write(to: options.output, options: .atomic)
    } catch {
        throw Stop(code: 1, message: "Couldn't write \(options.output.path()): \(error.localizedDescription)")
    }
    let seconds = (ContinuousClock.now - start).components.seconds
    print("Wrote \(catalogue.count) firmwares to \(options.output.path()) in \(seconds) s.")
    if !catalogue.problems.isEmpty {
        throw Stop(
            code: 4,
            message: catalogue.problems.joined(separator: " ") + " Firmwares only they list are from the previous list."
        )
    }
}

do {
    try await run()
} catch let stop as Stop {
    FileHandle.standardError.write(Data("fm1-catalogue: \(stop.message)\n".utf8))
    exit(stop.code)
} catch {
    FileHandle.standardError.write(Data("fm1-catalogue: \(error.localizedDescription)\n".utf8))
    exit(1)
}
