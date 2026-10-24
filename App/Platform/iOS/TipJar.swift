import StoreKit

/// The App Store's tips, and buying one.
@MainActor
@Observable
final class TipJar {
    enum Status: Equatable {
        case loading
        case ready
        case buying(Tip.ID)
        case thanked
        /// The App Store couldn't list the tips or take one.
        case failed
    }

    /// Whether tips are in-app purchases here, rather than a link to Ko-fi.
    static let isInApp = true

    private(set) var tips: [Tip] = []
    private(set) var status = Status.loading
    private var products: [Tip.ID: Product] = [:]
    private var updates: Task<Void, Never>?

    init() {
        // A tip bought while the app wasn't watching, such as one a parent approved later.
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.finish(result)
            }
        }
    }

    /// Fetches the tips and their prices, unless they're already here.
    func load() async {
        guard tips.isEmpty else { return }
        status = .loading
        do {
            let found = try await Product.products(for: Tips.productIDs)
            products = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            tips = found.sorted { $0.price < $1.price }
                .map { Tip(id: $0.id, name: $0.displayName, price: $0.displayPrice) }
            status = tips.isEmpty ? .failed : .ready
        } catch {
            status = .failed
        }
    }

    /// Buys a tip with `purchase`, which is SwiftUI's purchase action in the app: it shows the App
    /// Store's sheet in the right window.
    func buy(_ tip: Tip, with purchase: (Product) async throws -> Product.PurchaseResult) async {
        guard let product = products[tip.id] else { return }
        status = .buying(tip.id)
        do {
            switch try await purchase(product) {
            case .success(let result):
                await finish(result)
            case .pending, .userCancelled:
                status = .ready
            @unknown default:
                status = .ready
            }
        } catch {
            status = .failed
        }
    }

    /// Tips unlock nothing, so even one StoreKit can't verify is finished, and thanked for.
    private func finish(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
            await transaction.finish()
        }
        status = .thanked
    }
}
