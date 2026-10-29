import Foundation
import Testing

@testable import FMSwitch

/// Downloading the published list: trying again after a network failure, and when not to.
///
/// One at a time, as they share the download count.
@Suite(.serialized)
struct PublishedListTests {
    @Test func triesAgainAfterTheNetworkFails() async throws {
        let catalogue = try await list(failing: 2, with: URLError(.notConnectedToInternet)).load()
        let ids = catalogue.entries.map(\.id)
        #expect(ids == ["felucca"])
        #expect(downloads == 3)
    }

    @Test func givesUpAfterItsLastWait() async {
        let failure = await failure(of: list(failing: 10, with: URLError(.notConnectedToInternet)))
        #expect(failure == "unreachable")
        #expect(downloads == 4)
    }

    @Test func doesNotTryAgainWhenTheListIsMissing() async {
        let failure = await failure(of: list(failing: 10, with: Network.BadStatus(code: 404)))
        #expect(failure == "unusable")
        #expect(downloads == 1)
    }

    @Test func aCancelledDownloadIsNotAFailure() async {
        let failure = await failure(of: list(failing: 10, with: URLError(.cancelled)))
        #expect(failure == "cancelled")
        #expect(downloads == 1)
    }

    /// The published list, served after `failures` downloads that fail with `error`.
    private func list(failing failures: Int, with error: any Error) -> PublishedList {
        downloads = 0
        return PublishedList(
            fetch: { _ in
                downloads += 1
                if downloads <= failures { throw error }
                return try publishedList()
            },
            waits: [.zero, .zero, .zero])
    }

    /// How loading the list failed, in a word.
    private func failure(of list: PublishedList) async -> String {
        do {
            _ = try await list.load()
            return "loaded"
        } catch let failure as PublishedList.Failure {
            switch failure {
            case .unreachable: return "unreachable"
            case .unusable: return "unusable"
            }
        } catch {
            return error is CancellationError ? "cancelled" : "\(error)"
        }
    }
}

/// How many times the list's been downloaded in the running test.
nonisolated(unsafe) private var downloads = 0

/// A published list holding Felucca.
private func publishedList() throws -> Data {
    let list = MergedCatalogue(
        formatVersion: MergedCatalogue.currentFormat,
        builtAt: .now,
        hubUpdated: nil,
        entries: [CatalogueEntry(id: "felucca", name: "Felucca", listing: .hub)],
        problems: [])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(list)
}
