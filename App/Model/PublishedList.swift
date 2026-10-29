import Foundation

/// The firmware list fm-1.drewr.dev publishes, downloaded again after a short wait when the
/// network fails, as it often does for a moment as the app opens.
struct PublishedList: Sendable {
    enum Failure: Error {
        /// The list couldn't be reached, even after waiting and trying again.
        case unreachable(any Error)
        /// The list was reached but can't be used: it's missing, unreadable, or in a newer format.
        case unusable
    }

    /// Where fm-1.drewr.dev publishes the list.
    static let url = URL(literal: "https://fm-1.drewr.dev/firmwares.json")

    var fetch: PackageDiscovery.Fetch
    /// How long to wait before each new try.
    var waits: [Duration] = [.seconds(2), .seconds(4), .seconds(8)]

    /// - Throws: ``Failure``, or `CancellationError` when the refresh was cancelled.
    func load() async throws -> MergedCatalogue {
        var waits = waits[...]
        while true {
            let data: Data
            do {
                data = try await fetch(Self.url)
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                // A server answering "not found" won't answer differently in a few seconds.
                if let status = error as? Network.BadStatus, status.code < 500 { throw Failure.unusable }
                guard let wait = waits.popFirst() else { throw Failure.unreachable(error) }
                try await Task.sleep(for: wait)
                continue
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let catalogue = try? decoder.decode(MergedCatalogue.self, from: data), catalogue.isReadable,
                !catalogue.entries.isEmpty
            else { throw Failure.unusable }
            return catalogue
        }
    }
}
