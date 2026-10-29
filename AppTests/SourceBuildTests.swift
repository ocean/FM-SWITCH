import Foundation
import Testing

@testable import FMSwitch

/// Firmwares built from their source by GitHub Actions, as the firmware hub's signed records say.
struct SourceBuildTests {
    private static let sha = String(repeating: "ab", count: 32)
    private static let commit = String(repeating: "c", count: 40)

    /// A hub feed with one firmware, and the build record given for it.
    private func entry(provenance: String) throws -> CatalogueEntry {
        let json = """
            {"firmwares": [{"id": "bytemania", "name": "Bytemania", "kind": ["synth"], "version": "1.2.0",
            "pkg": "pkg/bytemania.fwsc", "product": "FM-1_900", "size": 1, "sha256": "\(Self.sha)",
            "provenance": \(provenance)}]}
            """
        return try #require(HubFeed.decode(Data(json.utf8)).entries().first)
    }

    @Test func countsASignedBuildOfThisPackage() throws {
        let entry = try entry(
            provenance: """
                {"sha256": "\(Self.sha)", "repo": "llozd/bytemania", "commit": "\(Self.commit)",
                "run": "https://github.com/llozd/bytemania/actions/runs/1", "verified": true, "by": "cryptography"}
                """)
        #expect(entry.isBuiltFromSource)
        #expect(entry.sourceBuild?.shortCommit == "ccccccc")
        let commitURL = "https://github.com/llozd/bytemania/commit/\(Self.commit)"
        #expect(entry.sourceBuild?.commitURL?.absoluteString == commitURL)
    }

    @Test func leavesOutRecordsTheHubDoesNot() throws {
        let other = String(repeating: "cd", count: 32)
        let records = [
            #"{"sha256": "\#(Self.sha)", "repo": "a/b", "commit": "\#(Self.commit)", "verified": false}"#,
            #"{"sha256": "\#(other)", "repo": "a/b", "commit": "\#(Self.commit)", "verified": true}"#,
            #"{"sha256": "\#(Self.sha)", "repo": "a/b", "commit": "c0ffee", "verified": true}"#,
            #"{"broken": true}"#,
        ]
        for record in records {
            #expect(try !entry(provenance: record).isBuiltFromSource, "\(record)")
        }
    }

    @Test func aNewerReleaseIsNotCountedUntilTheHubChecksIt() throws {
        var entry = try entry(
            provenance: #"{"sha256": "\#(Self.sha)", "repo": "a/b", "commit": "\#(Self.commit)", "verified": true}"#)
        entry.sha256 = String(repeating: "ef", count: 32)
        #expect(!entry.isBuiltFromSource)
    }

    @Test func offersTheFilterOnlyWhenAFirmwareIsBuiltFromSource() throws {
        let built = try entry(
            provenance: #"{"sha256": "\#(Self.sha)", "repo": "a/b", "commit": "\#(Self.commit)", "verified": true}"#)
        let plain = CatalogueEntry(id: "x", name: "X", kinds: ["synth"], listing: .hub)
        #expect(FirmwareFilter.scopes(for: [plain]) == [.all, .kind("synth")])
        #expect(FirmwareFilter.scopes(for: [plain, built]).last == .builtFromSource)
    }
}
