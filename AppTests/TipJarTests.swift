// StoreKit's test session only runs against an iPhone or iPad app. The Mac's tips are a link.
#if os(iOS)
    import StoreKit
    import StoreKitTest
    import Testing
    import UIKit

    @testable import FMSwitch

    /// Tips from FMSwitch.storekit, bought without the App Store's sheet.
    @MainActor
    @Suite(.serialized)
    struct TipJarTests {
        private let session: SKTestSession

        init() async throws {
            session = try SKTestSession(configurationFileNamed: "FMSwitch")
            session.disableDialogs = true
            session.clearTransactions()
            // A simulated error outlasts the test that set it.
            try await session.setSimulatedError(nil, forAPI: .purchase)
        }

        /// Buys in the test app's window, as the app's purchase action does.
        private func purchase(_ product: Product) async throws -> Product.PurchaseResult {
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            return try await product.purchase(confirmIn: scene)
        }

        @Test func listsTheThreeTipsSmallestFirst() async {
            let tipJar = TipJar()
            await tipJar.load()
            #expect(tipJar.tips.map(\.id) == Tips.productIDs)
            #expect(tipJar.status == .ready)
        }

        @Test func thanksThePersonForATip() async throws {
            let tipJar = TipJar()
            await tipJar.load()
            let tip = try #require(tipJar.tips.first)
            await tipJar.buy(tip, with: purchase)
            #expect(tipJar.status == .thanked)
            // Finished, so the App Store doesn't hand it back next time the app opens.
            var unfinished = 0
            for await result in StoreKit.Transaction.unfinished where result.unsafePayloadValue.productID == tip.id {
                unfinished += 1
            }
            #expect(unfinished == 0)
        }

        @Test func saysSoWhenTheAppStoreFails() async throws {
            let tipJar = TipJar()
            await tipJar.load()
            let tip = try #require(tipJar.tips.first)
            try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
            await tipJar.buy(tip, with: purchase)
            #expect(tipJar.status == .failed)
        }
    }
#endif
