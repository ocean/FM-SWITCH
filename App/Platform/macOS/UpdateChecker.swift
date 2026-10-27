import AppKit
import Foundation
import Observation

/// A published release of FM-SWITCH.
struct AppRelease: Equatable {
    var version: String
    /// The release's page, with its notes and download.
    var page: URL
}

/// Checks GitHub for a newer FM-SWITCH, since the Mac app comes from its releases rather than
/// the App Store.
///
/// It only says there's one: Download opens the release's page in the browser.
@MainActor
@Observable
final class UpdateChecker {
    /// What a check found.
    enum Outcome: Equatable {
        case newer(AppRelease)
        case latest
        case failed
    }

    static let latestRelease = URL(literal: "https://api.github.com/repos/ocean/FM-SWITCH/releases/latest")
    /// How long to leave between automatic checks.
    static let interval: TimeInterval = 24 * 60 * 60

    /// This app's version.
    let current: String
    /// Whether to check by itself, once a day.
    var checksAutomatically: Bool {
        didSet { defaults.set(checksAutomatically, forKey: Keys.checksAutomatically) }
    }
    /// The newest release, when it's newer than this app.
    private(set) var newest: AppRelease? {
        didSet {
            defaults.set(newest?.version, forKey: Keys.newestVersion)
            defaults.set(newest?.page.absoluteString, forKey: Keys.newestPage)
        }
    }
    /// The version the person said not now to.
    private var declined: String? { didSet { defaults.set(declined, forKey: Keys.declined) } }
    private var isChecking = false
    private let defaults: UserDefaults
    private let fetch: @Sendable (URL) async throws -> Data
    private let now: () -> Date

    init(
        current: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
        defaults: UserDefaults = .standard,
        fetch: @escaping @Sendable (URL) async throws -> Data = Network.fetch,
        now: @escaping () -> Date = Date.init
    ) {
        self.current = current
        self.defaults = defaults
        self.fetch = fetch
        self.now = now
        checksAutomatically = defaults.object(forKey: Keys.checksAutomatically) as? Bool ?? true
        declined = defaults.string(forKey: Keys.declined)
        // A release found earlier still counts, until this app is that version or newer.
        if let version = defaults.string(forKey: Keys.newestVersion),
            let page = defaults.string(forKey: Keys.newestPage).flatMap(URL.init(string:)),
            Self.isNewer(version, than: current)
        {
            newest = AppRelease(version: version, page: page)
        }
    }

    /// The newer release to show, unless the person said not now to it, or to a later one.
    var available: AppRelease? {
        guard let newest else { return nil }
        if let declined, !Self.isNewer(newest.version, than: declined) { return nil }
        return newest
    }

    /// Hides the newer release until there's a newer one again.
    func notNow() {
        declined = newest?.version
    }

    /// Checks once a day while the app is open, if checking automatically is on.
    func keepChecking() async {
        while !Task.isCancelled {
            await checkIfDue()
            try? await Task.sleep(for: .seconds(60 * 60))
        }
    }

    /// Checks if it's on and a day has passed since the last check that got an answer.
    func checkIfDue() async {
        guard checksAutomatically else { return }
        if let last = defaults.object(forKey: Keys.lastChecked) as? Date,
            now().timeIntervalSince(last) < Self.interval
        {
            return
        }
        await check()
    }

    /// Asks GitHub for the latest release and compares it with this app.
    @discardableResult
    func check() async -> Outcome {
        guard !isChecking else { return .failed }
        isChecking = true
        defer { isChecking = false }
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: await fetch(Self.latestRelease))
        } catch let status as Network.BadStatus where status.code == 404 {
            // Nothing's been released yet.
            defaults.set(now(), forKey: Keys.lastChecked)
            return .latest
        } catch {
            return .failed
        }
        guard !release.draft, !release.prerelease, let version = Self.version(fromTag: release.tagName),
            let page = URL(string: release.htmlURL)
        else { return .failed }
        defaults.set(now(), forKey: Keys.lastChecked)
        guard Self.isNewer(version, than: current) else {
            newest = nil
            return .latest
        }
        let found = AppRelease(version: version, page: page)
        newest = found
        return .newer(found)
    }

    /// Checks now and says what it found, for FM-SWITCH ▸ Check for Updates….
    func checkAndReport() async {
        let alert = NSAlert()
        switch await check() {
        case .newer(let release):
            alert.messageText = "FM-SWITCH \(release.version) is out"
            alert.informativeText = "You have \(current)."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.page)
            } else {
                notNow()
            }
        case .latest:
            alert.messageText = "You have the latest version"
            alert.informativeText = "FM-SWITCH \(current) is the newest."
            alert.runModal()
        case .failed:
            alert.messageText = "Couldn't check for a new version"
            alert.informativeText = "Check you're online, then try again."
            alert.runModal()
        }
    }

    /// The version in a tag such as "0.2.0" or "v0.2.0", or nil when it isn't one.
    static func version(fromTag tag: String) -> String? {
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        return parts(of: version) == nil ? nil : version
    }

    /// Whether `version` comes after `other`, comparing each number in turn, so 0.10.0 is after
    /// 0.9.0 and 1.0 is the same as 1.0.0.
    static func isNewer(_ version: String, than other: String) -> Bool {
        guard let new = parts(of: version), let old = parts(of: other) else { return false }
        for index in 0..<max(new.count, old.count) {
            let newPart = index < new.count ? new[index] : 0
            let oldPart = index < old.count ? old[index] : 0
            if newPart != oldPart { return newPart > oldPart }
        }
        return false
    }

    /// The numbers in a version such as "0.2.0", or nil when it has anything else.
    private static func parts(of version: String) -> [Int]? {
        var parts: [Int] = []
        for part in version.split(separator: ".", omittingEmptySubsequences: false) {
            guard part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            parts.append(number)
        }
        return parts
    }

    /// The parts of GitHub's latest release that matter here.
    private struct GitHubRelease: Decodable {
        var tagName: String
        var htmlURL: String
        var draft: Bool
        var prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    private enum Keys {
        static let checksAutomatically = "checksForUpdates"
        static let lastChecked = "updatesLastChecked"
        static let newestVersion = "newestVersion"
        static let newestPage = "newestVersionPage"
        static let declined = "declinedVersion"
    }
}
