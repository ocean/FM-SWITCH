import Foundation
import Testing

@testable import FMSwitch

/// Only M-VAVE's official firmware gets the V15 package on their downloads page.
struct OfficialPackageTests {
    private let v15 = URL(literal: "https://yms-file-store.oss-cn-hongkong.aliyuncs.com/software/firmware/FM-1.fwsc")
    private let downloadsPage = """
        <a href="https://yms-file-store.oss-cn-hongkong.aliyuncs.com/software/firmware/FM-1.fwsc">FM-1</a>
        """

    /// Links like the open firmware's, which point at M-VAVE's site but not at a package of its own.
    private var openFirmwareLinks: [CatalogueLink] {
        [
            CatalogueLink(label: "FM1 Workbench", url: URL(literal: "https://open.m-vave.com/fm1-workbench")),
            CatalogueLink(label: "Downloads", url: PackageDiscovery.mvaveDownloadsURL),
        ]
    }

    @Test func givesTheOfficialFirmwareM_VAVEsPackage() async throws {
        let page = Data(downloadsPage.utf8)
        let discovery = PackageDiscovery { _ in page }
        let found = try #require(
            await discovery.discover(name: "M-VAVE official firmware", links: openFirmwareLinks, isOfficial: true))
        #expect(found.url.lastPathComponent == "FM-1.fwsc")
        #expect(found.origin == .mvave)
    }

    @Test func doesNotGiveTheOpenFirmwareV15() async {
        let page = Data(downloadsPage.utf8)
        let discovery = PackageDiscovery { _ in page }
        #expect(await discovery.discover(name: "Official Open", links: openFirmwareLinks) == nil)
    }

    @Test func doesNotKeepV15FromAnEarlierListForTheOpenFirmware() {
        let open = CatalogueEntry(id: "fm1-editor-official-open", name: "Official Open", listing: .editor)
        var earlier = open
        earlier.packageURL = v15
        earlier.packageOrigin = .mvave
        earlier.version = "V15"
        let kept = CatalogueBuilder.fallBack(open, to: earlier)
        #expect(kept.packageURL == nil)
        #expect(kept.version == nil)
    }

    @Test func keepsAnEarlierPackageOtherwise() {
        let official = CatalogueEntry(id: "mvave-official", name: "M-VAVE", listing: .editor, isOfficial: true)
        var earlier = official
        earlier.packageURL = v15
        earlier.packageOrigin = .mvave
        #expect(CatalogueBuilder.fallBack(official, to: earlier).packageURL == earlier.packageURL)
    }
}
