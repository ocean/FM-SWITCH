import Foundation

/// The firmwares in konsumer's mutant.cloud (`mutant.cloud/firmware.json`), a list anyone can
/// add to by signing in with GitHub.
///
/// It lists FM-1 and SMK-37 firmwares and tools; only FM-1 firmwares are kept. Its packages aren't
/// taken: they're found from each firmware's links, as for aroum's FM1 Resource Hub.
struct MutantCloudListing: Sendable {
    static let defaultURL = URL(literal: "https://mutant.cloud/firmware.json")
    /// Where people read the list.
    static let pageURL = URL(literal: "https://mutant.cloud/")

    var entries: [ListedFirmware]

    /// Reads the list, or throws when it isn't mutant.cloud's JSON.
    init(json: Data) throws {
        let feed = try JSONDecoder().decode(Feed.self, from: json)
        let firmwares = feed.entries.compactMap(\.value).filter { $0.kind == "firmware" && $0.devices.contains("fm1") }
        entries = firmwares.map(\.listed)
    }

    /// mutant.cloud's tags as the kinds the other lists give, e.g. "groovebox" as "groove".
    ///
    /// Tags with no kind of their own, such as "generative", show only under All.
    static let kindsByTag = [
        "synth": "synth", "groovebox": "groove", "drums": "drums", "sampler": "drums", "chords": "chords",
        "tracker": "tracker", "game": "game",
    ]

    private struct Feed: Decodable {
        var entries: [Lossy<Firmware>]
    }

    /// One entry, or nil when it doesn't decode, so one odd entry doesn't lose the list.
    private struct Lossy<Value: Decodable>: Decodable {
        var value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    private struct Link: Decodable {
        var label: String
        var url: String
    }

    private struct Firmware: Decodable {
        var id: String
        var kind: String
        var name: String
        var author: String?
        var repo: String?
        var homepage: String?
        var links: [Link]?
        var devices: [String]
        var tags: [String]?
        var license: String?

        var listed: ListedFirmware {
            var listed: [(label: String, address: String)] = []
            if let repo { listed.append(("Source code", "https://github.com/\(repo)")) }
            if let homepage { listed.append(("Project site", homepage)) }
            listed += (links ?? []).map { ($0.label, $0.url) }
            var all: [CatalogueLink] = []
            for (label, address) in listed {
                guard let url = URL(string: address), url.scheme?.hasPrefix("http") == true else { continue }
                let link = CatalogueLink(label: label, url: url)
                if !all.contains(where: { $0.comparable == link.comparable }) { all.append(link) }
            }
            var kinds: [String] = []
            for kind in (tags ?? []).compactMap({ MutantCloudListing.kindsByTag[$0.lowercased()] })
            where !kinds.contains(kind) {
                kinds.append(kind)
            }
            var components = URLComponents(url: MutantCloudListing.pageURL, resolvingAgainstBaseURL: false)
            components?.fragment = "/p/\(id)"
            return ListedFirmware(
                name: name.trimmingCharacters(in: .whitespaces),
                author: author.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
                links: all,
                licence: license.flatMap { $0.isEmpty ? nil : $0 },
                kinds: kinds,
                page: components?.url,
                listID: id
            )
        }
    }
}
