import Foundation

/// A firmware's description as plain text to copy or share, say into Notes or an AI app.
enum FirmwareSharing {
    /// The firmware's name, maker, kinds, description and main links, one to a line.
    static func text(for entry: CatalogueEntry) -> String {
        var lines = ["\(entry.name) firmware for the M-VAVE FM-1"]
        if let author = entry.author { lines.append("By: \(author)") }
        if !entry.kinds.isEmpty { lines.append("Kinds: \(entry.kinds.joined(separator: ", "))") }
        if let what = entry.what { lines.append("Description: \(FirmwareDescription.plain(what))") }
        lines += entry.mainLinks.map { "\($0.label): \($0.url.absoluteString)" }
        return lines.joined(separator: "\n")
    }
}
