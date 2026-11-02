import Foundation

/// The firmware directory in aroum's FM1 Resource Hub (`github.com/aroum/fm1-custom-fw`), read
/// from its README.
///
/// The README lists each firmware as a table row under a section heading, such as
/// `| 3 | **Melodee by keremimo**<br>[GitHub](…) \| [Web Installer](…)<br>**License:** … | … |`.
/// Before 1 November 2026 it used numbered lines followed by a `**License:**` bullet, which are
/// still read. Only facts are taken, as ``ListedFirmware`` says, with the kinds from the section.
struct ResourceHubListing: Sendable {
    static let defaultURL = URL(literal: "https://raw.githubusercontent.com/aroum/fm1-custom-fw/main/README.md")
    /// Where people read the list.
    static let pageURL = URL(literal: "https://github.com/aroum/fm1-custom-fw")

    typealias Entry = ListedFirmware

    var entries: [Entry]

    init(markdown: String) {
        var entries: [Entry] = []
        var kinds: [String]?
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("#") {
                kinds = Self.kinds(forHeading: line)
                continue
            }
            guard let kinds else { continue }
            if let entry = Self.entry(fromRow: line, kinds: kinds) ?? Self.entry(fromLine: line, kinds: kinds) {
                entries.append(entry)
            } else if let licence = Self.licence(fromLine: line), let last = entries.indices.last,
                entries[last].licence == nil
            {
                entries[last].licence = licence
            }
        }
        self.entries = entries
    }

    /// The kinds for a section's firmwares, or nil outside the firmware sections.
    ///
    /// Section 1 lists firmwares, in 1.1 (sound), 1.2 (modular platforms), 1.3 (games and
    /// experiments) and 1.4 (patched stock firmware). Later sections are tools and references.
    static func kinds(forHeading line: String) -> [String]? {
        guard let match = line.firstMatch(of: #/^#+\s+(\d+)(?:\.(\d+))?/#) else { return nil }
        guard match.output.1 == "1" else { return nil }
        switch match.output.2 {
        case "2": return ["platform"]
        case "3": return ["game"]
        case "4": return ["patch"]
        default: return []
        }
    }

    /// A table row: `| 3 | **Name by Author**<br>[Label](url) \| …<br>**License:** … | … |`.
    ///
    /// The second cell has the name, the links (the first is the main one) and the licence, split
    /// by `<br>`. The third, the description, is left out.
    static func entry(fromRow line: String, kinds: [String]) -> Entry? {
        // Cells split at unescaped bars only; escaped ones separate the links.
        let cells = line.replacingOccurrences(of: "\\|", with: " ").split(
            separator: "|", omittingEmptySubsequences: false)
        let number = cells.count > 3 ? cells[1].trimmingCharacters(in: .whitespaces) : ""
        guard cells[0].allSatisfy(\.isWhitespace), !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let parts = cells[2].components(separatedBy: "<br>").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let title = parts[0].firstMatch(of: #/^\*\*(.+?)\*\*$/#), parts.count > 1,
            let links = links(in: parts[1])
        else { return nil }
        let (name, author) = nameAndAuthor(String(title.output.1))
        let licence = parts.lazy.compactMap { $0.firstMatch(of: #/^\*\*Licen[sc]e:\*\*\s*(.+)$/#) }.first
            .flatMap { cleanLicence(String($0.output.1)) }
        return Entry(name: name, author: author, links: links, licence: licence, kinds: kinds)
    }

    /// A numbered entry line, as the README had before its tables:
    /// `1. **[Name by Author](url) ([Label](url) | …):**`.
    static func entry(fromLine line: String, kinds: [String]) -> Entry? {
        guard let match = line.firstMatch(of: #/^\s*\d+\.\s+\*\*\[(.+?)\](\(https?://.*)$/#),
            let links = links(in: String(match.output.2))
        else { return nil }
        let (name, author) = nameAndAuthor(String(match.output.1))
        return Entry(name: name, author: author, links: links, licence: nil, kinds: kinds)
    }

    /// The Markdown links in `text`, the first labelled as the source code or project site and
    /// the rest as given; nil when there are none.
    ///
    /// The first may be bare, `(url)`, after a name taken separately.
    private static func links(in text: String) -> [CatalogueLink]? {
        let found = text.matches(of: #/(?:\[([^\]]+)\])?\((https?://[^\s)]+)\)/#).compactMap { match in
            URL(string: String(match.output.2)).map { (label: match.output.1.map(String.init), url: $0) }
        }
        guard let main = found.first else { return nil }
        var links = [
            CatalogueLink(label: main.url.host() == "github.com" ? "Source code" : "Project site", url: main.url)
        ]
        for other in found.dropFirst() {
            let link = CatalogueLink(label: other.label ?? "Link", url: other.url)
            if !links.contains(where: { $0.comparable == link.comparable }) {
                links.append(link)
            }
        }
        return links
    }

    /// The name and author, split at the first " by " of, say, "Felucca [Salt] by Chance Roth".
    static func nameAndAuthor(_ text: String) -> (String, String?) {
        let plain = text.replacingOccurrences(of: "\\", with: "").trimmingCharacters(in: .whitespaces)
        guard let range = plain.range(of: " by ") else { return (plain, nil) }
        let author = plain[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return (String(plain[..<range.lowerBound]), author.isEmpty ? nil : author)
    }

    /// The text of a `* **License:** …` bullet, without its closing full stop.
    static func licence(fromLine line: String) -> String? {
        guard let match = line.firstMatch(of: #/^\s*[*-]\s+\*\*Licen[sc]e:\*\*\s*(.+?)\s*$/#) else { return nil }
        return cleanLicence(String(match.output.1))
    }

    /// The licence alone, without what follows it or a closing full stop.
    private static func cleanLicence(_ listed: String) -> String? {
        var text = listed.trimmingCharacters(in: .whitespaces)
        // Only the licence itself: "Open Source (GPL-3.0). Based on Felucca." keeps the first part.
        if let end = text.range(of: ". ") { text = String(text[..<end.lowerBound]) }
        while text.hasSuffix(".") { text.removeLast() }
        return text.isEmpty ? nil : text
    }
}
