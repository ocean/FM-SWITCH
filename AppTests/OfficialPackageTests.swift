@_spi(Testing) import FM1Kit
import Foundation
import Testing

@testable import FMSwitch

/// Only M-VAVE's official firmware gets the package on their downloads page, V15 or V16.
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

    @MainActor @Test func givesTheOfficialFirmwareM_VAVEsPackage() async throws {
        let page = Data(downloadsPage.utf8)
        let package = try Data(contentsOf: #require(FirmwareLibrary.bundledOfficialURL))
        let discovery = PackageDiscovery { url in url.pathExtension == "fwsc" ? package : page }
        let found = try #require(
            await discovery.discover(name: "M-VAVE official firmware", links: openFirmwareLinks, isOfficial: true))
        #expect(found.url.lastPathComponent == "FM-1.fwsc")
        #expect(found.origin == .mvave)
        #expect(found.version == "V15")
        #expect(found.product == FM1Identity.officialV15.text)
        #expect(found.sha256 == OfficialFirmware.v15.sha256)
    }

    /// M-VAVE's link serves whichever is newest, so a package FM1Kit doesn't know isn't given.
    @Test func doesNotGiveAnUnknownPackageAtM_VAVEsLink() async throws {
        let page = Data(downloadsPage.utf8)
        let unknown = FwscPackage.sampleFile(product: "FM-1_017")
        let discovery = PackageDiscovery { url in url.pathExtension == "fwsc" ? unknown : page }
        #expect(
            await discovery.discover(name: "M-VAVE official firmware", links: openFirmwareLinks, isOfficial: true)
                == nil)
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
