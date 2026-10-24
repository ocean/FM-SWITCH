import StoreKit

/// The Mac app isn't from the Mac App Store, so tips go to Ko-fi and there's nothing to buy here.
@MainActor
@Observable
final class TipJar {
    enum Status: Equatable {
        case loading
        case ready
        case buying(Tip.ID)
        case thanked
        case failed
    }

    static let isInApp = false

    let tips: [Tip] = []
    let status = Status.ready

    func load() async {}

    func buy(_: Tip, with _: (Product) async throws -> Product.PurchaseResult) async {}
}
