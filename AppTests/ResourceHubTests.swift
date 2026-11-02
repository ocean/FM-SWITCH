import Foundation
import Testing

@testable import FMSwitch

/// Reading aroum's FM1 Resource Hub, and merging it into the firmware list.
struct ResourceHubTests {
    /// Made-up entries in the layout of aroum's FM1 Resource Hub README.
    static let sample = """
        # FM1 Resource Hub
        ## 1. Custom & Alternative Firmwares
        #### 1.1.1. A Synth Family
         1. **[Zeta Synth by Ada (ada-dev)](https://github.com/ada-dev/zeta) ([Web Installer](https://a.dev/z/) | [Manual](https://a.dev/m/)):**
           * **License:** Open Source (GPL-3.0-only). Based on another firmware.
           * **Features:** Lots of them.
         2. **[Mono A by Bo](https://github.com/bo/monorepo) ([Web Installer](https://bo.github.io/monorepo/a/)):**
           * **License:** Open Source (MIT).
         3. **[Mono B by Bo](https://github.com/bo/monorepo/tree/main/b):**
         4. **[baud girl Custom Firmware Mod](https://baudgirl.com/):**
           * **License:** Closed Source.
        ### 1.3. Gaming, Emulators & Non-Audio Ports
         1. **[Pong by Cy](https://github.com/cy/pong):**
        ## 3. External References & Resources
         1. **[An Editor by Di](https://github.com/di/editor):**
        """

    /// Made-up entries in the table layout the README has had since 1 November 2026.
    static let tableSample = #"""
        ## 1. Custom & Alternative Firmwares
        #### 1.1.1. A Synth Family
        | # | Name, Author, License & Links | Description & Features |
        |---|-------------------------------|------------------------|
        | 1 | **Zeta Synth by Ada (ada-dev)**<br>[GitHub](https://github.com/ada-dev/zeta) \#
        \| [Web Installer](https://a.dev/z/) \| [Manual](https://a.dev/m/)<br>**License:** Open Source \#
        (GPL-3.0-only). Based on another firmware. | **Polyphony:** 8 voices \| lots.<br>**Features:** Many. |
        | 2 | **Hersen (赫森) by Hu**<br>[Project Link](https://store.example.com/hersen/) \| [GitHub](https://github.com/hu/hersen)<br>**License:** Closed Source. | Grooves. |
        ### 1.3. Gaming, Emulators & Non-Audio Ports
        | # | Name, Author, License & Links | Description & Features |
        |---|-------------------------------|------------------------|
        | 1 | **Pong by Cy**<br>[GitHub](https://github.com/cy/pong) | A game. |
        ## 3. External References & Resources
        | 1 | **An Editor by Di**<br>[GitHub](https://github.com/di/editor) | An editor. |
        """#

    static func link(_ address: String) -> [CatalogueLink] {
        [CatalogueLink(label: "Source", url: URL(string: address) ?? URL(literal: "https://example.com"))]
    }

    @Test func readsFirmwaresButNotTheOtherSections() {
        let listing = ResourceHubListing(markdown: Self.sample)
        #expect(
            listing.entries.map(\.name) == ["Zeta Synth", "Mono A", "Mono B", "baud girl Custom Firmware Mod", "Pong"])
        let zeta = listing.entries[0]
        #expect(zeta.author == "Ada (ada-dev)")
        #expect(zeta.licence == "Open Source (GPL-3.0-only)")
        #expect(zeta.links.map(\.label) == ["Source code", "Web Installer", "Manual"])
        #expect(listing.entries[3].links.first?.label == "Project site")
        #expect(listing.entries[2].licence == nil)
        #expect(listing.entries[4].kinds == ["game"])
    }

    @Test func readsTheTableLayout() {
        let listing = ResourceHubListing(markdown: Self.tableSample)
        #expect(listing.entries.map(\.name) == ["Zeta Synth", "Hersen (赫森)", "Pong"])
        let zeta = listing.entries[0]
        #expect(zeta.author == "Ada (ada-dev)")
        #expect(zeta.licence == "Open Source (GPL-3.0-only)")
        #expect(zeta.links.map(\.label) == ["Source code", "Web Installer", "Manual"])
        #expect(zeta.links.last?.url.absoluteString == "https://a.dev/m/")
        #expect(listing.entries[1].links.map(\.label) == ["Project site", "GitHub"])
        #expect(listing.entries[1].licence == "Closed Source")
        #expect(listing.entries[2].licence == nil)
        #expect(listing.entries[2].kinds == ["game"])
    }

    @Test func mergesWithoutJoiningFirmwaresThatShareARepository() throws {
        let listed = CatalogueBuilder.merge(
            hub: [
                CatalogueEntry(
                    id: "zeta", name: "Zeta", links: Self.link("https://github.com/ada-dev/zeta"), listing: .hub),
                CatalogueEntry(
                    id: "mono", name: "Mono A", links: Self.link("https://github.com/bo/monorepo"), listing: .hub),
            ],
            editor: EditorListing(html: CatalogueTests.editorSample).entries,
            editorURL: EditorListing.defaultURL
        )
        let entries = CatalogueBuilder.merge(
            resourceHub: ResourceHubListing(markdown: Self.sample).entries, into: listed)

        // Zeta shares a repository. Mono A and B share one too, so only Mono A's name joins it.
        let zeta = try #require(entries.first { $0.id == "zeta" })
        #expect(zeta.listing == [.hub, .resourceHub])
        #expect(zeta.licence == "Open Source (GPL-3.0-only)")
        #expect(entries.first { $0.id == "mono" }?.listing == [.hub, .resourceHub])
        #expect(entries.contains { $0.id == "resource-hub-mono-b" && $0.listing == .resourceHub })
        // fm1-editor.com's Baud Girl page sits under baudgirl.com, and the names start the same way.
        #expect(entries.first { $0.id == "fm1-editor-baud-girl" }?.listing.contains(.resourceHub) == true)
        #expect(!entries.contains { $0.id == "resource-hub-baud-girl-custom-firmware-mod" })
        #expect(entries.first { $0.id == "resource-hub-pong" }?.kinds == ["game"])
    }

    @Test func needsMatchingNamesBeforeASharedSiteJoinsTwoFirmwares() {
        let sloop = CatalogueEntry(
            id: "sloopdx", name: "sloopDX", links: Self.link("https://dx7.example.com/"), listing: .hub)
        #expect(!CatalogueBuilder.matches(sloop, links: Self.link("https://dx7.example.com/doom/"), name: "FM-1 Doom"))
        #expect(CatalogueBuilder.matches(sloop, links: [], name: "Something / sloopDX"))
    }
}
