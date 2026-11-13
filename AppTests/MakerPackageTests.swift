import FM1Kit
import Foundation
import Testing

@testable import FMSwitch

/// Downloading The Firmware Hub's firmwares from their makers, as the hub's terms ask.
struct MakerPackageTests {
    private static let package = Data("a firmware".utf8)
    private static let sha256 = FwscPackage.sha256Hex(package)
    private static let commit = String(repeating: "c", count: 40)

    private static func hubEntry(size: Int = package.count) -> CatalogueEntry {
        CatalogueEntry(
            id: "tuna",
            name: "Tuna",
            packageURL: URL(string: "https://thefirmwarehub.com/fw/tuna.fwsc"),
            packageOrigin: .hub,
            size: size,
            sha256: sha256,
            repo: "delirioux/tuna",
            listing: .hub
        )
    }

    /// Answers each address listed, and fails the rest.
    private static func fetching(_ answers: [String: Data]) -> PackageDiscovery.Fetch {
        { url in
            guard let data = answers[url.absoluteString] else { throw URLError(.fileDoesNotExist) }
            return data
        }
    }

    private static func releases(digest: String?, size: Int = package.count) -> Data {
        let field = digest.map { #""digest": "sha256:\#($0)","# } ?? ""
        return Data(
            """
            [{"tag_name": "v1.2", "draft": false, "prerelease": false, "assets": [
              {"name": "tuna-1.2.fwsc", "size": \(size), \(field)
               "browser_download_url": "https://github.com/delirioux/tuna/releases/download/v1.2/tuna-1.2.fwsc"}]}]
            """.utf8)
    }

    private static let releasesURL = "https://api.github.com/repos/delirioux/tuna/releases?per_page=30"
    private static let assetURL = "https://github.com/delirioux/tuna/releases/download/v1.2/tuna-1.2.fwsc"

    @Test func takesTheReleaseFileWithTheHubsChecksum() async throws {
        let makers = MakerPackage(fetch: Self.fetching([Self.releasesURL: Self.releases(digest: Self.sha256)]))
        let found = try #require(await makers.find(for: Self.hubEntry()))
        #expect(found.url.absoluteString == Self.assetURL)
        #expect(found.origin == .githubRelease)
    }

    @Test func readsAReleaseFileGitHubGivesNoChecksumFor() async throws {
        let makers = MakerPackage(
            fetch: Self.fetching([
                Self.releasesURL: Self.releases(digest: nil), Self.assetURL: Self.package,
            ]))
        #expect(await makers.find(for: Self.hubEntry())?.url.absoluteString == Self.assetURL)
    }

    @Test func takesAFileKeptInTheRepositoryPinnedToItsCommit() async throws {
        let tree = """
            {"tree": [
              {"path": "docs/other.fwsc", "type": "blob", "size": 3},
              {"path": "docs/firmware/tuna.fwsc", "type": "blob", "size": \(Self.package.count)}]}
            """
        let raw = "https://raw.githubusercontent.com/delirioux/tuna/\(Self.commit)/docs/firmware/tuna.fwsc"
        let makers = MakerPackage(
            fetch: Self.fetching([
                Self.releasesURL: Data("[]".utf8),
                "https://api.github.com/repos/delirioux/tuna/commits/HEAD": Data(#"{"sha": "\#(Self.commit)"}"#.utf8),
                "https://api.github.com/repos/delirioux/tuna/git/trees/\(Self.commit)?recursive=1": Data(tree.utf8),
                raw: Self.package,
            ]))
        let found = try #require(await makers.find(for: Self.hubEntry()))
        #expect(found.url.absoluteString == raw)
        #expect(found.origin == .projectPage)
    }

    @Test func takesAFileOnAPagesSiteBuiltFromABranch() async throws {
        let pages =
            #"{"html_url": "https://delirioux.github.io/tuna/", "build_type": "legacy", "source": {"branch": "gh-pages", "path": "/"}}"#
        let tree = #"{"tree": [{"path": "firmware/tuna.fwsc", "type": "blob", "size": \#(Self.package.count)}]}"#
        let raw = "https://raw.githubusercontent.com/delirioux/tuna/\(Self.commit)/firmware/tuna.fwsc"
        let makers = MakerPackage(
            fetch: Self.fetching([
                "https://api.github.com/repos/delirioux/tuna/pages": Data(pages.utf8),
                "https://api.github.com/repos/delirioux/tuna/commits/gh-pages": Data(
                    #"{"sha": "\#(Self.commit)"}"#.utf8),
                "https://api.github.com/repos/delirioux/tuna/git/trees/\(Self.commit)?recursive=1": Data(tree.utf8),
                raw: Self.package,
            ]))
        let found = try #require(await makers.find(for: Self.hubEntry()))
        #expect(found.url.absoluteString == raw)
        #expect(found.origin == .projectPage)
    }

    @Test func takesAFileAPagesSiteBuiltByAWorkflowWasDeployedWith() async throws {
        let pages = #"{"html_url": "https://delirioux.github.io/tuna/", "build_type": "workflow"}"#
        let site = "https://delirioux.github.io/tuna/firmware/tuna.fwsc"
        let makers = MakerPackage(
            fetch: Self.fetching(["https://api.github.com/repos/delirioux/tuna/pages": Data(pages.utf8)]),
            pagesFiles: { repo, root in
                #expect(repo == "delirioux/tuna")
                return [
                    PagesFile(url: root.appending(path: "firmware/other.fwsc"), contents: Data("other".utf8)),
                    PagesFile(url: root.appending(path: "firmware/tuna.fwsc"), contents: Self.package),
                ]
            })
        let found = try #require(await makers.find(for: Self.hubEntry()))
        #expect(found.url.absoluteString == site)
        #expect(found.origin == .projectPage)
    }

    @Test func listsAFirmwareItsMakerDoesntPublishWithLinksOnly() async {
        let builder = CatalogueBuilder(fetch: Self.fetching([:]))
        let entry = await builder.fromMakers([Self.hubEntry()], previous: []).first
        #expect(entry?.packageURL == nil)
        #expect(entry?.packageOrigin == .hub)
        #expect(entry?.isDownloadable == false)
    }

    @Test func keepsTheMakersAddressFoundEarlierForTheSamePackage() async {
        var earlier = Self.hubEntry()
        earlier.packageURL = URL(string: Self.assetURL)
        earlier.packageOrigin = .githubRelease
        let builder = CatalogueBuilder(fetch: Self.fetching([:]))
        let kept = await builder.fromMakers([Self.hubEntry()], previous: [earlier]).first
        #expect(kept?.packageURL?.absoluteString == Self.assetURL)
        // Not for another package.
        var other = earlier
        other.sha256 = String(repeating: "0", count: 64)
        #expect(await builder.fromMakers([Self.hubEntry()], previous: [other]).first?.packageURL == nil)
    }

    @Test func neverDownloadsFromTheHubInAListSavedBefore() {
        #expect(!Self.hubEntry().isDownloadable)
    }

    @Test func linksToTheFirmwaresCardOnTheHub() throws {
        let entry = try #require(HubFeed.decode(Data(CatalogueTests.hubSample.utf8)).entries().first)
        #expect(entry.links.last?.url.absoluteString == "https://thefirmwarehub.com/#fw-zp12")
    }

    @Test func anAppBuildingTheListKeepsTheHubsFirmwaresWithoutReadingIt() async throws {
        var earlier = Self.hubEntry()
        earlier.packageURL = URL(string: Self.assetURL)
        earlier.packageOrigin = .githubRelease
        let builder = CatalogueBuilder(
            fetch: { url in
                #expect(url != HubFeed.defaultURL)
                switch url {
                case EditorListing.defaultURL: return Data(CatalogueTests.editorSample.utf8)
                default: throw URLError(.fileDoesNotExist)
                }
            }, readsTheHub: false)
        let catalogue = try await builder.build(previous: [earlier])
        #expect(catalogue.entries.first { $0.id == "tuna" }?.packageURL?.absoluteString == Self.assetURL)
        #expect(!catalogue.problems.contains("The Firmware Hub couldn't be read."))
    }

    @Test func refusesOnTheNewerChipOnlyWhatTheHubListsAsKnowingTheOlder() {
        var check = SwitchingCheck(isRead: true)
        check.knowsOnlyFirstChip = ["ZEN-1"]
        check.hubListsFirstChipOnly = ["ZEN-1"]
        #expect(!check.refusesFlashChip)
        check.hasNewerFlashChip = true
        #expect(check.refusesFlashChip)
        #expect(!check.asksAboutFlashChip)
    }

    @Test func asksBeforeInstallingWhatOnlyLooksLikeItKnowsTheOlderChip() {
        var check = SwitchingCheck(isRead: true)
        check.knowsOnlyFirstChip = ["ZEN-1"]
        #expect(!check.asksAboutFlashChip)
        check.hasNewerFlashChip = true
        #expect(!check.refusesFlashChip)
        #expect(check.asksAboutFlashChip)
    }
}
