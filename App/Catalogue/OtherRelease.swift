import Foundation

extension CatalogueEntry {
    /// A release of the same firmware on the other track: stable beside a test release, or the
    /// other way round.
    struct OtherRelease: Codable, Sendable, Hashable {
        var version: String?
        var date: String?
        /// Whether it's a test release.
        var beta: Bool
        var packageURL: URL?
        var packageOrigin: PackageOrigin?
        var product: String?
        var size: Int?
        var sha256: String?
        var builds: [Build]?
        var build: String?
        var releaseURL: URL?

        /// The release `entry` points at.
        init(of entry: CatalogueEntry) {
            version = entry.version
            date = entry.date
            beta = entry.beta
            packageURL = entry.packageURL
            packageOrigin = entry.packageOrigin
            product = entry.product
            size = entry.size
            sha256 = entry.sha256
            builds = entry.builds
            build = entry.build
            releaseURL = entry.releaseURL
        }
    }

    /// The entry pointing at its other release, with the release it pointed at as the other one.
    func choosingOtherRelease() -> Self {
        guard let other = otherRelease else { return self }
        var entry = self
        entry.version = other.version
        entry.date = other.date
        entry.beta = other.beta
        entry.packageURL = other.packageURL
        entry.packageOrigin = other.packageOrigin
        entry.product = other.product
        entry.size = other.size
        entry.sha256 = other.sha256
        entry.builds = other.builds
        entry.build = other.build
        entry.releaseURL = other.releaseURL
        entry.otherRelease = OtherRelease(of: self)
        return entry
    }
}
