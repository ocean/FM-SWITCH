import Foundation
import Testing

@testable import FMSwitch

/// Reading mutant.cloud, and keeping the firmwares of a list that can't be read.
struct ListSourceTests {
    /// Made-up entries in the layout of mutant.cloud's firmware.json.
    static let mutantCloudSample = Data(
        """
        {"count": 5, "entries": [
          {"id": "zp12-fork", "kind": "firmware", "name": "ZP-12", "author": "zvenson", "repo": "zvenson/zp12",
           "devices": ["fm1"], "tags": ["drums"], "license": "GPL-3.0", "links": [], "description": "Not taken."},
          {"id": "orange-cat", "kind": "firmware", "name": "Orange Cat", "author": "Sea", "repo": "sea/orange-cat",
           "homepage": "https://sea.example.com/cat/", "devices": ["fm1", "smk37"], "tags": ["groovebox", "generative"],
           "license": "MIT", "links": [{"label": "Install", "url": "https://sea.example.com/cat/install/"}]},
          {"id": "an-editor", "kind": "tool", "name": "An Editor", "devices": ["fm1"], "links": []},
          {"id": "smk-only", "kind": "firmware", "name": "SMK Only", "devices": ["smk37"], "links": []},
          {"id": "odd", "kind": "firmware", "name": 7, "devices": ["fm1"]}
        ]}
        """.utf8)

    @Test func readsOnlyFM1FirmwaresFromMutantCloud() throws {
        let listing = try MutantCloudListing(json: Self.mutantCloudSample)
        #expect(listing.entries.map(\.name) == ["ZP-12", "Orange Cat"])
        let cat = listing.entries[1]
        #expect(cat.author == "Sea")
        #expect(cat.licence == "MIT")
        #expect(cat.kinds == ["groove"])
        #expect(cat.links.map(\.label) == ["Source code", "Project site", "Install"])
        #expect(cat.page?.absoluteString == "https://mutant.cloud/#/p/orange-cat")
    }

    @Test func mergesMutantCloudByRepository() throws {
        let hub = try HubFeed.decode(Data(CatalogueTests.hubSample.utf8)).entries(relativeTo: HubFeed.defaultURL)
        let entries = CatalogueBuilder.merge(
            mutantCloud: try MutantCloudListing(json: Self.mutantCloudSample).entries, into: hub)
        #expect(entries.first { $0.id == "zp12" }?.listing == [.hub, .mutantCloud])
        let cat = try #require(entries.first { $0.id == "mutant-cloud-orange-cat" })
        #expect(cat.listing == .mutantCloud)
        #expect(cat.what == nil)
        #expect(cat.links.last?.url.absoluteString == "https://mutant.cloud/#/p/orange-cat")
        #expect(!cat.isHardwareTested)
    }

    @Test func keepsTheFirmwaresOfAListThatCantBeRead() async throws {
        let previous = [
            CatalogueEntry(
                id: "zp12",
                name: "zp12",
                links: ResourceHubTests.link("https://github.com/zvenson/zp12"),
                listing: [.hub, .resourceHub]),
            CatalogueEntry(
                id: "resource-hub-pong",
                name: "Pong",
                links: ResourceHubTests.link("https://github.com/cy/pong"),
                listing: .resourceHub),
            CatalogueEntry(
                id: "gone", name: "Gone", links: ResourceHubTests.link("https://github.com/no/gone"), listing: .hub),
        ]
        let catalogue = try await Self.builder(failing: ResourceHubListing.defaultURL).build(previous: previous)
        #expect(catalogue.problems == ["aroum's FM1 Resource Hub couldn't be read."])
        let zp12 = try #require(catalogue.entries.first { $0.id == "zp12" })
        #expect(zp12.listing.isSuperset(of: [.hub, .resourceHub, .mutantCloud]))
        #expect(catalogue.entries.first { $0.id == "resource-hub-pong" }?.listing == .resourceHub)
        // A firmware a list that was read has dropped stays dropped.
        #expect(!catalogue.entries.contains { $0.id == "gone" })
    }

    @Test func saysWhichListCantBeReadWithoutAnEarlierList() async throws {
        let catalogue = try await Self.builder(failing: MutantCloudListing.defaultURL).build()
        #expect(catalogue.problems == ["mutant.cloud couldn't be read."])
        #expect(catalogue.entries.contains { $0.id == "resource-hub-pong" })
        #expect(catalogue.entries.first { $0.id == "zp12" }?.listing.contains(.mutantCloud) == false)
    }

    /// A builder whose lists are the samples, except `failing`, which can't be reached.
    static func builder(failing: URL) -> CatalogueBuilder {
        CatalogueBuilder(fetch: { url in
            switch url {
            case failing: throw URLError(.cannotConnectToHost)
            case HubFeed.defaultURL: return Data(CatalogueTests.hubSample.utf8)
            case EditorListing.defaultURL: return Data(CatalogueTests.editorSample.utf8)
            case ResourceHubListing.defaultURL: return Data(ResourceHubTests.sample.utf8)
            case MutantCloudListing.defaultURL: return mutantCloudSample
            default: throw URLError(.fileDoesNotExist)
            }
        })
    }
}
