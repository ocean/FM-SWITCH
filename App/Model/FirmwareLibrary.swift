import FM1Kit
import Foundation
import Observation

/// A firmware package saved on the phone, ready to flash offline.
struct StoredFirmware: Codable, Identifiable, Hashable {
    enum Source: String, Codable {
        case catalogue
        case official
        case imported
    }

    /// What's known about a package before it's saved, beyond what the package itself says.
    struct Details {
        var name: String
        var version: String
        var author: String?
        var source: Source
        var catalogueID: String?
        var packageURL: URL?
        var build: String?
    }

    var id: String
    var name: String
    var version: String
    var author: String?
    var product: String
    var sha256: String
    var size: Int
    var fileName: String
    var source: Source
    var catalogueID: String?
    /// Where it was downloaded from, to recognise packages that have no published checksum.
    var packageURL: URL?
    /// Which build, for a release that comes in several (e.g. "1core").
    var build: String?
    var savedAt: Date
}

/// The saved firmwares: downloads, imports, and the official firmware.
///
/// Packages are kept in a Firmwares folder, in iCloud Drive when it's on (see ``SharedStorage``),
/// each with what's known about it in a file of its own in the folder's hidden `.details` folder.
/// Each device only ever adds or removes whole files, so devices sharing the folder never write
/// over each other.
///
/// M-VAVE's V15 comes with the app (it's Apache-2.0, from M-VAVE's open-source repository), so the
/// official firmware is always to hand for recovery. It's read from the app itself rather than
/// saved, so devices sharing the folder don't each add a copy.
@MainActor
@Observable
final class FirmwareLibrary {
    private(set) var items: [StoredFirmware] = []
    private(set) var downloading: Set<String> = []
    /// Each saved package's loader hash, worked out when first needed.
    @ObservationIgnored private var loaderHashes: [String: String?] = [:]

    private(set) var directory: URL
    private let bundledOfficial: URL?
    /// The copy of V15 that comes with the app, as a saved firmware.
    private let builtInOfficial: StoredFirmware?

    /// The copy of V15 that comes with the app.
    static let bundledOfficialURL = Bundle.main.url(forResource: "FM-1_015", withExtension: "fwsc")

    init(directory: URL = SharedStorage.onDevice.firmwares, bundledOfficial: URL? = bundledOfficialURL) {
        self.directory = directory
        self.bundledOfficial = bundledOfficial
        builtInOfficial = bundledOfficial.flatMap(Self.builtInOfficial(at:))
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    private var detailsDirectory: URL { directory.appending(path: ".details", directoryHint: .isDirectory) }

    /// Moves every saved firmware into `newDirectory` and keeps them there from now on: into
    /// iCloud Drive, once it's known to be on.
    func move(to newDirectory: URL) async {
        guard newDirectory.standardizedFileURL != directory.standardizedFileURL else { return }
        await SharedStorage.move(directory, into: newDirectory)
        directory = newDirectory
        loaderHashes = [:]
        reload()
    }

    /// The saved V15: the firmware other firmwares install from, and the one to go back to.
    ///
    /// Only V15 counts, as M-VAVE's other official firmware (FM1 Open) doesn't do either job.
    var official: StoredFirmware? {
        items.first { $0.source == .official && $0.sha256 == OfficialFirmware.v15.sha256 }
    }

    var totalBytes: Int {
        items.reduce(0) { $0 + $1.size }
    }

    var sortedItems: [StoredFirmware] {
        items.sorted { lhs, rhs in
            if (lhs.source == .official) != (rhs.source == .official) { return lhs.source == .official }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// The saved copy of exactly this release: the same checksum when one is published,
    /// otherwise the same download address.
    func stored(for entry: CatalogueEntry) -> StoredFirmware? {
        if let sha256 = entry.sha256 {
            return items.first { $0.sha256 == sha256 }
        }
        guard let packageURL = entry.packageURL else { return nil }
        return items.first { $0.catalogueID == entry.id && $0.packageURL == packageURL }
    }

    /// A saved copy of an older release of this catalogue firmware.
    func outdated(for entry: CatalogueEntry) -> StoredFirmware? {
        guard stored(for: entry) == nil else { return nil }
        return items.first { item in
            item.catalogueID == entry.id
                && (entry.version.map { ReleaseVersion.isNewer($0, than: item.version) } ?? true)
        }
    }

    /// A saved copy of this release in another build than the one picked.
    func otherBuild(for entry: CatalogueEntry) -> StoredFirmware? {
        guard stored(for: entry) == nil, outdated(for: entry) == nil else { return nil }
        return items.first { $0.catalogueID == entry.id }
    }

    func url(for item: StoredFirmware) -> URL {
        if item == builtInOfficial, let bundledOfficial { return bundledOfficial }
        return directory.appending(path: item.fileName)
    }

    /// Reads a saved package, waiting for it to arrive first if another device saved it to
    /// iCloud Drive and it isn't here yet.
    func loadPackage(_ item: StoredFirmware) async throws -> FwscPackage {
        let url = url(for: item)
        try await SharedStorage.download(url)
        return try FwscPackage(data: Data(contentsOf: url))
    }

    /// The saved firmwares whose package can finish the update `loader` is waiting to do.
    ///
    /// Each package brings its own update loader, and a loader reports `ota-` and the identity of
    /// the package that started it, so that package can finish it. There are two exceptions:
    /// - M-VAVE's loader always reports `ota-FM-1_015`, so any package that brings it will do.
    /// - The loader of armed open firmware reports `ota-FM1C_` and the start of the armed build
    ///   ID, so the package with that build ID is the one.
    func packages(thatCanFinish loader: FM1Identity) -> [StoredFirmware] {
        sortedItems.filter { item in
            if let armedBuildPrefix = loader.armedBuildPrefix {
                return Self.buildID(of: item).hasPrefix(armedBuildPrefix.lowercased())
            }
            return FM1Identity.loaderPrefix + item.product == loader.text
                || (loader.text == Self.stockLoaderIdentity
                    && loaderSHA256(of: item) == OfficialFirmware.stockLoaderSHA256)
        }
    }

    /// The build ID open firmware is armed with to install `item`, in lower-case hex: M-VAVE's
    /// published one for its own releases, otherwise the package's SHA-256, as M-VAVE's updater
    /// uses.
    private static func buildID(of item: StoredFirmware) -> String {
        OfficialFirmware.known.first { $0.sha256 == item.sha256 }?.buildID.hex.lowercased() ?? item.sha256
    }

    /// What M-VAVE's update loader reports, whichever package started it.
    static let stockLoaderIdentity = "ota-FM-1_015"

    private func loaderSHA256(of item: StoredFirmware) -> String? {
        if let known = loaderHashes[item.id] { return known }
        // A package still on its way from iCloud Drive can't be checked yet.
        let hash = (try? Data(contentsOf: url(for: item))).flatMap { try? FwscPackage(data: $0).loaderSHA256 }
        loaderHashes[item.id] = hash
        return hash
    }

    // MARK: - Adding.

    /// Downloads a catalogue firmware, checks whatever is published about it (size, hash,
    /// identity), checks it reads as an FM-1 package, and saves it, replacing older releases.
    ///
    /// M-VAVE's own firmware is recognised by its hash and kept as the official firmware.
    @discardableResult
    func download(_ entry: CatalogueEntry) async throws -> StoredFirmware {
        guard let packageURL = entry.packageURL else { throw Failure.noPackage }
        downloading.insert(entry.id)
        defer { downloading.remove(entry.id) }

        let data = try await fetch(packageURL)
        if let size = entry.size, data.count != size { throw Failure.hashMismatch }
        if let sha256 = entry.sha256, FwscPackage.sha256Hex(data) != sha256 { throw Failure.hashMismatch }
        let package = try FwscPackage(data: data)
        if let product = entry.product, package.product != product {
            throw Failure.productMismatch(expected: product, found: package.product)
        }
        if OfficialFirmware.matching(package) == .v15 {
            return try saveOfficial(
                data, package: package, name: OfficialFirmware.v15.name, catalogueID: entry.id, from: packageURL)
        }
        guard !entry.isOfficial else { throw Failure.notOfficial }
        for older in items where older.catalogueID == entry.id {
            remove(older)
        }
        let details = StoredFirmware.Details(
            name: entry.name,
            version: entry.version ?? package.product,
            author: entry.author,
            source: .catalogue,
            catalogueID: entry.id,
            packageURL: packageURL,
            build: entry.build
        )
        return try save(data, package: package, details: details)
    }

    /// Finds FM-1.fwsc on M-VAVE's downloads page and saves it, if it is the known official release.
    @discardableResult
    func downloadOfficialFromMVAVE() async throws -> StoredFirmware {
        guard let found = await PackageDiscovery(fetch: Network.fetch).officialPackage() else {
            throw Failure.officialNotFound
        }
        return try await importOfficial(from: found.url)
    }

    /// Imports a `.fwsc` the user picked in Files.
    ///
    /// Official firmware is recognised by its hash.
    @discardableResult
    func importFile(at url: URL) throws -> StoredFirmware {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try add(data, fallbackName: url.deletingPathExtension().lastPathComponent)
    }

    /// Downloads the official firmware from a link the user supplies; anything else is refused.
    @discardableResult
    func importOfficial(from remoteURL: URL) async throws -> StoredFirmware {
        let data = try await fetch(remoteURL)
        let package = try FwscPackage(data: data)
        guard OfficialFirmware.matching(package) == .v15 else { throw Failure.notOfficial }
        return try add(data, fallbackName: "Official")
    }

    private func add(_ data: Data, fallbackName: String) throws -> StoredFirmware {
        let package = try FwscPackage(data: data)
        let official = OfficialFirmware.matching(package)
        if official == .v15 {
            return try saveOfficial(
                data, package: package, name: OfficialFirmware.v15.name, catalogueID: nil, from: nil)
        }
        if let existing = existing(package) { return existing }
        // M-VAVE's other releases (FM1 Open) are named and credited, but aren't the official V15.
        let details = StoredFirmware.Details(
            name: official?.name ?? fallbackName,
            version: package.product,
            author: official == nil ? nil : "M-VAVE",
            source: .imported
        )
        return try save(data, package: package, details: details)
    }

    /// The V15 that comes with the app, after checking it's the known release.
    private static func builtInOfficial(at url: URL) -> StoredFirmware? {
        guard let data = try? Data(contentsOf: url), let package = try? FwscPackage(data: data),
            OfficialFirmware.matching(package) == .v15
        else { return nil }
        return StoredFirmware(
            id: package.sha256,
            name: OfficialFirmware.v15.name,
            version: "Official",
            author: "M-VAVE",
            product: package.product,
            sha256: package.sha256,
            size: data.count,
            fileName: url.lastPathComponent,
            source: .official,
            savedAt: .distantPast
        )
    }

    /// Saves M-VAVE's own firmware, or returns the copy already saved.
    @discardableResult
    private func saveOfficial(
        _ data: Data,
        package: FwscPackage,
        name: String,
        catalogueID: String?,
        from packageURL: URL?
    ) throws -> StoredFirmware {
        if let existing = existing(package) { return existing }
        let details = StoredFirmware.Details(
            name: name,
            version: "Official",
            author: "M-VAVE",
            source: .official,
            catalogueID: catalogueID,
            packageURL: packageURL
        )
        return try save(data, package: package, details: details)
    }

    /// The saved copy of exactly this package, if there is one.
    private func existing(_ package: FwscPackage) -> StoredFirmware? {
        items.first { $0.sha256 == package.sha256 }
    }

    private func fetch(_ url: URL) async throws -> Data {
        do {
            return try await Network.fetch(url)
        } catch {
            throw Failure.download(error.localizedDescription)
        }
    }

    private func save(_ data: Data, package: FwscPackage, details: StoredFirmware.Details) throws -> StoredFirmware {
        let fileName = freeFileName(for: details, package: package)
        try FileManager.default.createDirectory(at: detailsDirectory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: fileName), options: .atomic)
        let item = StoredFirmware(
            id: package.sha256,
            name: details.name,
            version: details.version,
            author: details.author,
            product: package.product,
            sha256: package.sha256,
            size: data.count,
            fileName: fileName,
            source: details.source,
            catalogueID: details.catalogueID,
            packageURL: details.packageURL,
            build: details.build,
            savedAt: .now
        )
        try JSONEncoder().encode(item).write(to: detailsURL(for: item), options: .atomic)
        items.removeAll { $0.id == item.id }
        items.append(item)
        return item
    }

    /// A file name people can recognise in Files and the Finder, such as "Felucca 1.2.fwsc".
    private func freeFileName(for details: StoredFirmware.Details, package: FwscPackage) -> String {
        let version = details.version == package.product ? nil : details.version
        let words = [details.name, version, details.build].compactMap(\.self).joined(separator: " ")
        let base = String(words.map { "/:\\".contains($0) ? "-" : $0 })
        let name = "\(base).fwsc"
        return SharedStorage.exists(directory.appending(path: name)) ? "\(base) \(package.sha256.prefix(8)).fwsc" : name
    }

    private func detailsURL(for item: StoredFirmware) -> URL {
        detailsDirectory.appending(path: "\(item.sha256).json")
    }

    // MARK: - Removing.

    func remove(_ item: StoredFirmware) {
        guard item != builtInOfficial else { return }
        try? FileManager.default.removeItem(at: url(for: item))
        try? FileManager.default.removeItem(at: detailsURL(for: item))
        items.removeAll { $0.id == item.id }
    }

    /// Empties the cache, except for the official firmware.
    func clear() {
        for item in items where item.source != .official {
            remove(item)
        }
    }

    // MARK: - Reading.

    /// Reads the saved firmwares from the folder again, as another device may have changed it.
    ///
    /// Firmwares whose details haven't arrived from iCloud Drive yet are left out until they have.
    func reload() {
        let decoder = JSONDecoder()
        var found = SharedStorage.contents(of: detailsDirectory).compactMap { url -> StoredFirmware? in
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(StoredFirmware.self, from: data)
        }
        // Leave out any whose package has gone.
        found.removeAll { !SharedStorage.exists(directory.appending(path: $0.fileName)) }
        if let builtInOfficial, !found.contains(where: { $0.sha256 == builtInOfficial.sha256 }) {
            found.append(builtInOfficial)
        }
        items = found
    }
}
