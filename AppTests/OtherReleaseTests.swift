import Foundation
import Testing

@testable import FMSwitch

/// A firmware with a stable release and a newer test one offers both, whichever the list chose.
struct OtherReleaseTests {
    @Test func aTestReleaseOffersTheStableOne() async throws {
        guard
            case .newer(let test) = try await ReleaseCheckTests.check.check(
                ReleaseCheckTests.melodee(version: "1.4.0-rc.3", beta: true))
        else {
            Issue.record("Expected a newer pre-release.")
            return
        }
        let stable = try #require(test.otherRelease)
        #expect(stable.version == "1.3.7")
        #expect(!stable.beta)
        #expect(stable.builds?.map(\.name) == ["1core", "standard"])

        let picked = test.choosingOtherRelease()
        #expect(picked.version == "1.3.7")
        #expect(!picked.beta)
        #expect(picked.otherRelease?.version == "v1.4.0-rc.4")
        #expect(picked.otherRelease?.beta == true)
        #expect(picked.choosingOtherRelease() == test)
    }

    @Test func aStableReleaseOffersANewerTestOne() async throws {
        guard
            case .upToDate(let stable) = try await ReleaseCheckTests.check.check(
                ReleaseCheckTests.melodee(version: "1.3.7", sha256: "dd"))
        else {
            Issue.record("Expected up to date.")
            return
        }
        #expect(!stable.beta)
        #expect(stable.otherRelease?.version == "1.4.0-rc.4")
        #expect(stable.otherRelease?.beta == true)
    }

    @Test func anOlderTestReleaseIsntOffered() throws {
        let releases = try JSONDecoder().decode(
            [GitHubRelease].self, from: Data(ReleaseCheckTests.melodeeReleases.utf8))
        let newer = ReleaseCheckTests.melodee(version: "1.5.0")
        #expect(ReleaseCheck.otherRelease(beside: newer, in: releases, build: nil) == nil)
    }

    /// The hub marks versions before 1.0 as betas, but GitHub says which releases are tests.
    @Test func aStableReleaseTheListCallsATestIsntOfferedAsItsOwnStable() async throws {
        guard
            case .upToDate(let stable) = try await ReleaseCheckTests.check.check(
                ReleaseCheckTests.melodee(version: "1.3.7", beta: true, sha256: "dd"))
        else {
            Issue.record("Expected up to date.")
            return
        }
        #expect(!stable.beta)
        #expect(stable.otherRelease?.version == "1.4.0-rc.4")
    }

    @Test func onlyTestLikeVersionsAreTestReleases() {
        for version in ["1.6.0-rc.6", "2.5-b28-test", "1.0-test", "Beta6", "0.10.0-beta"] {
            #expect(ReleaseVersion.looksLikePreRelease(version), "\(version)")
        }
        for version in ["0.3.7", "0.26.0", "0.9.9-par10-30f05b3", "v1.2", "fantasma-v1.1"] {
            #expect(!ReleaseVersion.looksLikePreRelease(version), "\(version)")
        }
    }
}
