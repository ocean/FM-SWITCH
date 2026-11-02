import Foundation

/// A firmware as a list that has no packages gives it: aroum's FM1 Resource Hub, or mutant.cloud.
///
/// Only facts are taken: the name, author, links, licence and kinds. Neither list's text has a
/// licence, so their descriptions are left out.
struct ListedFirmware: Sendable, Hashable {
    var name: String
    var author: String?
    /// The firmware's main link, then the others the list gives, e.g. its web installer.
    var links: [CatalogueLink]
    /// The licence as the list gives it, e.g. "Open Source (GPL-3.0-only)".
    var licence: String?
    /// Such as "game" for a game.
    var kinds: [String] = []
    /// The firmware's own page on the list, when it has one.
    var page: URL?
    /// The list's ID for it, when it has one, for the firmware's ID in the merged list.
    var listID: String?
}
