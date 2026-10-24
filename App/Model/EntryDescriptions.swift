/// Plain descriptions of where a firmware comes from, for the firmware pages' details.
extension CatalogueEntry {
    /// The lists the firmware is on, e.g. "Firmware hub + fm1-editor.com".
    var listedOn: String {
        [
            listing.contains(.hub) ? "Firmware hub" : nil,
            listing.contains(.editor) ? "fm1-editor.com" : nil,
            listing.contains(.resourceHub) ? "FM1 Resource Hub" : nil,
        ]
        .compactMap(\.self)
        .joined(separator: " + ")
    }

    /// Where the firmware's file comes from.
    var packageSource: String {
        switch packageOrigin {
        case .hub: "Firmware hub mirror"
        case .githubRelease: "GitHub release"
        case .publisherManifest: "The publisher's site"
        case .projectPage: "The project's page"
        case .mvave: "M-VAVE's downloads"
        case nil: "None found"
        }
    }
}
