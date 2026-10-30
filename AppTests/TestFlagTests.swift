import Testing

@testable import FMSwitch

/// Lists built before the app knew the firmware hub marks every 0.x version a beta.
@MainActor
struct TestFlagTests {
    /// A firmware flagged as a test release, with its file from `origin`.
    private func flagged(_ id: String, _ version: String, from origin: CatalogueEntry.PackageOrigin) -> CatalogueEntry {
        CatalogueEntry(id: id, name: id, version: version, beta: true, packageOrigin: origin, listing: .hub)
    }

    /// Each firmware's test flag once the list is corrected, by ID.
    private func corrected(_ entries: [CatalogueEntry]) -> [String: Bool] {
        let list = MergedCatalogue(
            formatVersion: MergedCatalogue.currentFormat,
            builtAt: .now,
            hubUpdated: nil,
            entries: entries,
            problems: [])
        let fixed = CatalogueStore.correctingTestFlags(of: list).entries
        return Dictionary(uniqueKeysWithValues: fixed.map { ($0.id, $0.beta) })
    }

    @Test func dropsTheHubsFlagFromAPlainVersion() {
        let entries = [flagged("estampie", "0.3.7", from: .hub), flagged("jiant", "1.6.0-rc.6", from: .hub)]
        #expect(corrected(entries) == ["estampie": false, "jiant": true])
    }

    @Test func keepsGitHubsPreReleaseFlag() {
        #expect(corrected([flagged("radio", "1.3", from: .githubRelease)]) == ["radio": true])
    }

    @Test func marksAnUntaggedBuildAsATest() {
        let commit = "047d21f6154ff6f86c7d3dc4b90f8d5e3320c300"
        let entry = CatalogueEntry(id: "kawa", name: "KAWA", version: commit, packageOrigin: .hub, listing: .hub)
        let list = MergedCatalogue(
            formatVersion: MergedCatalogue.currentFormat,
            builtAt: .now,
            hubUpdated: nil,
            entries: [entry],
            problems: [])
        let fixed = CatalogueStore.correctingTestFlags(of: list).entries
        #expect(fixed.map(\.beta) == [true])
        #expect(fixed.map(\.version) == ["047d21f"])
    }

    @Test(arguments: [
        ("047d21f6154ff6f86c7d3dc4b90f8d5e3320c300", true), ("047d21f", true), ("20261020", false),
        ("0.3.7", false), ("beef", false),
    ])
    func recognisesACommit(version: String, isCommit: Bool) {
        #expect(ReleaseVersion.isCommit(version) == isCommit)
    }
}
