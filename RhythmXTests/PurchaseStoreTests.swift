import XCTest
import StoreKit
import StoreKitTest
@testable import RhythmX

/// Purchase flows against the local `RhythmX.storekit` configuration (Review Focus 4 and 5).
/// The session is loaded from the file directly, so these tests do not depend on the scheme setting.
@MainActor
final class PurchaseStoreTests: XCTestCase {
    private var session: SKTestSession!
    private var defaults: UserDefaults!
    private var suiteName: String!
    /// Injected clock. Tests move it forward to expire a pass without waiting.
    private var clock = Date()

    private static var configurationURL: URL {
        get throws {
            try XCTUnwrap(Bundle(for: PurchaseStoreTests.self).url(forResource: "RhythmX", withExtension: "storekit"),
                          "RhythmX.storekit must be a resource of the RhythmXTests bundle")
        }
    }

    override func setUp() async throws {
        try await super.setUp()
        session = try SKTestSession(contentsOf: try Self.configurationURL)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        // Nothing from an earlier test may still be waiting in the queue.
        for await result in Transaction.unfinished {
            if case .verified(let t) = result { await t.finish() }
        }
        suiteName = "test.purchaseStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        clock = Date()
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        if let suiteName { defaults?.removePersistentDomain(forName: suiteName) }
        defaults = nil
        try await super.tearDown()
    }

    private func makeStore(listensForUpdates: Bool = false) -> PurchaseStore {
        PurchaseStore(defaults: defaults, calendar: .current, now: { [unowned self] in self.clock }, listensForUpdates: listensForUpdates)
    }

    private func unfinishedCount() async -> Int {
        var n = 0
        for await _ in Transaction.unfinished { n += 1 }
        return n
    }

    private func waitUntil(_ timeout: TimeInterval = 8, _ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if await condition() || Date() >= deadline { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// A purchase made outside the app (another device, Ask to Buy, or an app that died before finishing). The
    /// StoreKit daemon publishes it a moment after `buyProduct` returns, so wait until it is queued as unfinished.
    @discardableResult
    private func buyOutsideTheApp(_ id: String) async throws -> Transaction {
        let transaction = try await session.buyProduct(identifier: id)
        await waitUntil { await self.isUnfinished(transaction.id) }
        return transaction
    }

    private func isUnfinished(_ id: UInt64) async -> Bool {
        for await result in Transaction.unfinished where result.unsafePayloadValue.id == id { return true }
        return false
    }

    private func plusIsCurrentlyEntitled() async -> Bool {
        for await result in Transaction.currentEntitlements
        where PurchaseStore.ProductID.plus.contains(result.unsafePayloadValue.productID) { return true }
        return false
    }

    private func isCurrentEntitlement(_ id: UInt64) async -> Bool {
        for await result in Transaction.currentEntitlements where result.unsafePayloadValue.id == id { return true }
        return false
    }

    /// Skips, with the reason in the test report, when StoreKit itself has lost a transaction that the test
    /// session holds: `found` is false although `session.allTransactions()` contains `id`. This is a StoreKit
    /// Testing defect of the iOS 26.5 Simulator, not app behavior: its storekitd logs "Could not decode purchase
    /// result: DecodingError.keyNotFound: Key 'original-transaction-id' not found" for every Product.purchase(),
    /// so the purchase is missing from Transaction.currentEntitlements for a moment after it returns and its
    /// finish() is lost, and a purchase made with SKTestSession.buyProduct drops the previous purchase from
    /// Transaction.unfinished. On a device, or once Apple fixes the runtime, `found` is true and the test runs.
    private func skipIfSimulatorStoreKitLost(_ id: UInt64, as kind: String, found: () async -> Bool) async throws {
        #if targetEnvironment(simulator)
        guard session.allTransactions().contains(where: { UInt64($0.identifier) == id }) else { return }
        if await found() { return }
        throw XCTSkip("Simulator StoreKit Testing lost transaction \(id) (\(kind)) that SKTestSession holds. "
                      + "Known iOS 26.5 Simulator storekitd defect (original-transaction-id decode error); run on a device.")
        #endif
    }

    private func latestPlusIsRevoked(_ id: String) async -> Bool {
        guard let latest = await Transaction.latest(for: id) else { return false }
        return latest.unsafePayloadValue.revocationDate != nil
    }

    // MARK: Configuration file

    func testLoadsTheThreeProducts() async throws {
        let store = makeStore()
        await store.load()
        XCTAssertEqual(Set(store.products.map(\.id)), Set(PurchaseStore.ProductID.all))
        XCTAssertEqual(store.products.count, 3)

        let monthly = try XCTUnwrap(store.products.first { $0.id == PurchaseStore.ProductID.monthly })
        let yearly = try XCTUnwrap(store.products.first { $0.id == PurchaseStore.ProductID.yearly })
        let dayPass = try XCTUnwrap(store.products.first { $0.id == PurchaseStore.ProductID.dayPass })
        XCTAssertEqual(monthly.price, Decimal(string: "1.99"))
        XCTAssertEqual(yearly.price, Decimal(string: "9.99"))
        XCTAssertEqual(dayPass.price, Decimal(string: "0.99"))
        XCTAssertEqual(monthly.type, .autoRenewable)
        XCTAssertEqual(yearly.type, .autoRenewable)
        XCTAssertEqual(dayPass.type, .consumable)
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod, .monthly)
        XCTAssertEqual(yearly.subscription?.subscriptionPeriod, .yearly)
        XCTAssertEqual(monthly.subscription?.subscriptionGroupID, yearly.subscription?.subscriptionGroupID, "one subscription group")
        XCTAssertEqual(PurchaseStore.ProductID.monthly, "beta.Rhythm.plus.1month")
        XCTAssertEqual(PurchaseStore.ProductID.yearly, "beta.Rhythm.plus.yearly")
        XCTAssertEqual(PurchaseStore.ProductID.dayPass, "beta.Rhythm.pdf.daypass")
    }

    func testYearlyIntroOfferIsThreeDayFree() async throws {
        let store = makeStore()
        await store.load()
        let yearly = try XCTUnwrap(store.products.first { $0.id == PurchaseStore.ProductID.yearly })
        let offer = try XCTUnwrap(yearly.subscription?.introductoryOffer, "yearly carries an introductory offer")
        XCTAssertEqual(offer.paymentMode, .freeTrial)
        XCTAssertEqual(offer.period.unit, .day)
        XCTAssertEqual(offer.period.value, 3)
        XCTAssertEqual(offer.periodCount, 1)
        XCTAssertEqual(offer.price, 0)

        let monthly = try XCTUnwrap(store.products.first { $0.id == PurchaseStore.ProductID.monthly })
        XCTAssertNil(monthly.subscription?.introductoryOffer, "monthly has no trial")

        // Group name straight from the file (the StoreKit API only exposes the localized display name).
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: try Self.configurationURL)) as? [String: Any]
        let groups = try XCTUnwrap(json?["subscriptionGroups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0]["name"] as? String, "RhythmX Plus")
    }

    // MARK: Plus

    func testPlusPurchaseMadeOutsideTheAppIsAppliedOnLaunch() async throws {
        try await buyOutsideTheApp(PurchaseStore.ProductID.monthly)
        let store = makeStore()
        await store.load()

        XCTAssertTrue(store.isPlus)
        XCTAssertTrue(store.canExportPDF)
        XCTAssertFalse(store.hasDayPass)
        let cached = try XCTUnwrap(Entitlement.load(from: defaults).plusExpiry, "expiry is cached for the widgets")
        XCTAssertGreaterThan(cached, clock)
        let unfinished = await unfinishedCount()
        XCTAssertEqual(unfinished, 0, "the subscription transaction is finished once the entitlement is recorded")
    }

    func testPurchasePlusYearlyThroughStoreKit() async throws {
        let store = makeStore()
        await store.load()
        try await store.purchasePlus(yearly: true)
        // Asked straight away, as the app does: if StoreKit itself does not list the new subscription yet, the
        // app could not have seen it either (iOS 26.5 Simulator defect, see skipIfSimulatorStoreKitLost).
        let bought = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == PurchaseStore.ProductID.yearly })
        let listed = await isCurrentEntitlement(UInt64(bought.identifier))
        if !store.isPlus {
            try await skipIfSimulatorStoreKitLost(UInt64(bought.identifier), as: "entitlement") { listed }
        }
        XCTAssertTrue(store.isPlus)
        XCTAssertTrue(store.canExportPDF)
        XCTAssertEqual(session.allTransactions().count, 1)
        XCTAssertEqual(session.allTransactions().first?.productIdentifier, PurchaseStore.ProductID.yearly)
        let unfinished = await unfinishedCount()
        XCTAssertEqual(unfinished, 0)
    }

    func testExpiredPlusKeepsThreeDayGraceForWidgetsOnly() async throws {
        try await buyOutsideTheApp(PurchaseStore.ProductID.monthly)
        let store = makeStore()
        await store.load()
        XCTAssertTrue(store.isPlus)

        try session.expireSubscription(productIdentifier: PurchaseStore.ProductID.monthly)
        await waitUntil { await !self.plusIsCurrentlyEntitled() }
        await store.refreshEntitlements()

        let expiry = try XCTUnwrap(store.entitlement.plusExpiry, "a lapsed subscription keeps its last expiry so the grace can apply offline")
        XCTAssertLessThanOrEqual(expiry, Date())
        XCTAssertTrue(store.entitlement.isPlus(now: expiry.addingTimeInterval(2 * 86_400)), "grace")
        XCTAssertFalse(store.entitlement.isPlus(now: expiry.addingTimeInterval(3 * 86_400 + 1)))
        XCTAssertFalse(store.entitlement.canExportPDF(now: expiry.addingTimeInterval(1)), "exports have no grace")
        XCTAssertEqual(Entitlement.load(from: defaults).plusExpiry, expiry, "widgets read the same cached date")

        // Inside the grace: the widgets (reading the cache) still show Plus, the app itself does not. A lapsed
        // user opening the paywall sees the purchase options, not "Plus is active".
        clock = expiry.addingTimeInterval(86_400)
        XCTAssertTrue(store.entitlement.isPlus(now: clock), "widget grace")
        XCTAssertFalse(store.isPlus, "the app has no grace")
        XCTAssertFalse(store.canExportPDF)

        // Fully lapsed: the widget reads the cache and degrades to the upgrade prompt (Review Focus 5).
        clock = expiry.addingTimeInterval(4 * 86_400)
        XCTAssertFalse(store.entitlement.isPlus(now: clock))
        XCTAssertFalse(store.isPlus)
        XCTAssertFalse(store.canExportPDF)
    }

    func testRefundedPlusClearsTheCache() async throws {
        let transaction = try await buyOutsideTheApp(PurchaseStore.ProductID.monthly)
        let store = makeStore()
        await store.load()
        XCTAssertTrue(store.isPlus)

        try session.refundTransaction(identifier: UInt(transaction.id))
        await waitUntil { await self.latestPlusIsRevoked(PurchaseStore.ProductID.monthly) }
        await store.refreshEntitlements()
        XCTAssertNil(store.entitlement.plusExpiry)
        XCTAssertFalse(store.isPlus)
        XCTAssertNil(defaults.object(forKey: PersistenceKeys.plusExpiry))
    }

    // MARK: Day Pass (Review Focus 4)

    func testInterruptedDayPassPurchaseRecoversOnceWithoutSecondCharge() async throws {
        // The purchase went through but the app died before the unlock was stored and the transaction finished.
        let transaction = try await buyOutsideTheApp(PurchaseStore.ProductID.dayPass)
        let before = await unfinishedCount()
        XCTAssertEqual(before, 1)

        let store = makeStore()
        await store.load()

        XCTAssertTrue(store.hasDayPass)
        XCTAssertTrue(store.canExportPDF)
        XCTAssertFalse(store.isPlus)
        // The pass is the day she paid for: it ends at the start of the local day after the purchase date
        // StoreKit recorded, not the day the app happened to recover the transaction.
        let expected = Entitlement.dayPassExpiry(purchasedAt: transaction.purchaseDate, calendar: .current)
        XCTAssertEqual(store.entitlement.dayPassExpiry, expected, "start of the local day after the purchase")
        XCTAssertEqual(Entitlement.load(from: defaults).dayPassExpiry, expected)
        var unfinished = await unfinishedCount()
        XCTAssertEqual(unfinished, 0, "finished once recorded")
        XCTAssertEqual(defaults.stringArray(forKey: PersistenceKeys.dayPassTransactions)?.count, 1)

        // A second launch, a restore and a later clock must not grant again or extend the pass.
        clock = clock.addingTimeInterval(60)
        let relaunched = makeStore()
        await relaunched.load()
        await relaunched.restore()
        XCTAssertEqual(relaunched.entitlement.dayPassExpiry, expected)
        XCTAssertEqual(defaults.stringArray(forKey: PersistenceKeys.dayPassTransactions)?.count, 1)
        XCTAssertEqual(session.allTransactions().count, 1, "no second charge")
        unfinished = await unfinishedCount()
        XCTAssertEqual(unfinished, 0)
    }

    func testDayPassGrantStoresExpiryBeforeFinishAndOnlyOnce() async {
        let store = makeStore()
        var finishCalls = 0
        var expiryAtFinish: Date?

        let granted = await store.grantDayPass(transactionID: 4_242, purchaseDate: clock) {
            finishCalls += 1
            expiryAtFinish = Entitlement.load(from: self.defaults).dayPassExpiry
        }
        let expected = Entitlement.dayPassExpiry(purchasedAt: clock, calendar: .current)
        XCTAssertTrue(granted)
        XCTAssertEqual(finishCalls, 1)
        XCTAssertEqual(expiryAtFinish, expected, "the expiry is on disk before finish() runs")
        XCTAssertEqual(store.entitlement.dayPassExpiry, expected)

        // The same transaction delivered again (Transaction.updates after Transaction.unfinished) is finished
        // but grants nothing, even when the clock has moved on.
        clock = clock.addingTimeInterval(3600)
        let again = await store.grantDayPass(transactionID: 4_242, purchaseDate: clock) { finishCalls += 1 }
        XCTAssertFalse(again)
        XCTAssertEqual(finishCalls, 2, "a duplicate is still finished so StoreKit stops redelivering it")
        XCTAssertEqual(store.entitlement.dayPassExpiry, expected)
        XCTAssertEqual(defaults.stringArray(forKey: PersistenceKeys.dayPassTransactions), ["4242"])
    }

    func testDayPassExpiryComesFromPurchaseDateNotRecoveryTime() async throws {
        // Bought just after midnight, recovered at noon (the app died in between): the pass still ends at the
        // next midnight after the purchase, which is the same day. Recovery time plays no part.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let purchaseDate = today.addingTimeInterval(1)
        clock = today.addingTimeInterval(12 * 3600)
        let store = makeStore()

        let granted = await store.grantDayPass(transactionID: 1, purchaseDate: purchaseDate) {}
        XCTAssertTrue(granted)
        let expected = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertEqual(store.entitlement.dayPassExpiry, expected)
        XCTAssertEqual(store.entitlement.dayPassExpiry, Entitlement.dayPassExpiry(purchasedAt: purchaseDate, calendar: calendar))
        XCTAssertTrue(store.hasDayPass)

        // A second, older transaction (bought yesterday, recovered now) cannot shorten the pass: max wins.
        let yesterdayNoon = today.addingTimeInterval(-12 * 3600)
        var finishCalls = 0
        let older = await store.grantDayPass(transactionID: 2, purchaseDate: yesterdayNoon) { finishCalls += 1 }
        XCTAssertFalse(older, "yesterday's pass is over; nothing to grant")
        XCTAssertEqual(finishCalls, 1, "still finished once")
        XCTAssertEqual(store.entitlement.dayPassExpiry, expected, "today's pass is untouched")
        XCTAssertEqual(defaults.stringArray(forKey: PersistenceKeys.dayPassTransactions), ["1", "2"])
    }

    func testDayPassRecoveredAfterItsDayEndedGrantsNothingButIsFinishedOnce() async {
        // The purchase went through two days ago and the app never ran again until now: the day she paid for
        // is gone. No pass is granted (the expiry stays nil), the id is recorded, and the transaction is finished
        // once so StoreKit stops redelivering it.
        let twoDaysAgo = clock.addingTimeInterval(-2 * 86_400)
        let store = makeStore()
        var finishCalls = 0

        let granted = await store.grantDayPass(transactionID: 7, purchaseDate: twoDaysAgo) { finishCalls += 1 }
        XCTAssertFalse(granted)
        XCTAssertEqual(finishCalls, 1)
        XCTAssertNil(store.entitlement.dayPassExpiry, "an expired result is simply no pass")
        XCTAssertNil(Entitlement.load(from: defaults).dayPassExpiry)
        XCTAssertFalse(store.hasDayPass)
        XCTAssertEqual(defaults.stringArray(forKey: PersistenceKeys.dayPassTransactions), ["7"])

        // Redelivered: nothing changes, and it is finished again.
        let again = await store.grantDayPass(transactionID: 7, purchaseDate: twoDaysAgo) { finishCalls += 1 }
        XCTAssertFalse(again)
        XCTAssertEqual(finishCalls, 2)
        XCTAssertNil(store.entitlement.dayPassExpiry)
    }

    func testPurchaseDayPassThroughStoreKit() async throws {
        let store = makeStore()
        await store.load()
        try await store.purchaseDayPass()
        XCTAssertTrue(store.hasDayPass)
        XCTAssertEqual(store.entitlement.dayPassExpiry, Entitlement.dayPassExpiry(purchasedAt: clock, calendar: .current))
        XCTAssertEqual(session.allTransactions().count, 1)
        let unfinished = await unfinishedCount()
        XCTAssertEqual(unfinished, 0)
    }

    func testExpiredDayPassCannotBeRestored() async throws {
        try await buyOutsideTheApp(PurchaseStore.ProductID.dayPass)
        let store = makeStore()
        await store.load()
        let expiry = try XCTUnwrap(store.entitlement.dayPassExpiry)
        XCTAssertTrue(store.hasDayPass)

        // The next local day: the pass is over.
        clock = expiry.addingTimeInterval(1)
        XCTAssertFalse(store.hasDayPass)
        XCTAssertFalse(store.canExportPDF)

        // Restore Purchases, a relaunch and a refresh bring nothing back: consumables are not restorable,
        // the stored instant stays where it was, and nothing is charged.
        await store.restore()
        XCTAssertFalse(store.hasDayPass)
        XCTAssertEqual(store.entitlement.dayPassExpiry, expiry)

        let relaunched = makeStore()
        await relaunched.load()
        await relaunched.restore()
        XCTAssertFalse(relaunched.hasDayPass)
        XCTAssertEqual(relaunched.entitlement.dayPassExpiry, expiry)
        XCTAssertEqual(Entitlement.load(from: defaults).dayPassExpiry, expiry)
        XCTAssertEqual(session.allTransactions().count, 1)
    }

    func testPlusWinsOverDayPassInTheStore() async throws {
        // Plus first, then the pass. In the iOS 26.5 Simulator a purchase made through SKTestSession drops the
        // previous purchase from Transaction.unfinished; bought the other way round, the pass vanishes from the
        // queue (a consumable is not an entitlement) and StoreKit no longer offers it to the app at all. Plus
        // stays in Transaction.currentEntitlements either way, so this order keeps the scenario intact.
        let plus = try await buyOutsideTheApp(PurchaseStore.ProductID.yearly)
        let pass = try await buyOutsideTheApp(PurchaseStore.ProductID.dayPass)
        await waitUntil { await self.isUnfinished(pass.id) }
        try await skipIfSimulatorStoreKitLost(plus.id, as: "entitlement") { await self.isCurrentEntitlement(plus.id) }
        try await skipIfSimulatorStoreKitLost(pass.id, as: "unfinished transaction") { await self.isUnfinished(pass.id) }
        let store = makeStore()
        await store.load()
        XCTAssertTrue(store.isPlus)
        XCTAssertTrue(store.hasDayPass)
        let passExpiry = try XCTUnwrap(store.entitlement.dayPassExpiry)
        clock = passExpiry.addingTimeInterval(1)
        XCTAssertFalse(store.hasDayPass)
        XCTAssertTrue(store.canExportPDF, "Plus exports after the pass has ended")
    }

    // MARK: Verification (Apple Calendar removal waits for it)

    func testEntitlementIsVerifiedOnlyAfterStoreKitAnswers() async throws {
        try await buyOutsideTheApp(PurchaseStore.ProductID.yearly)
        let store = makeStore()
        XCTAssertFalse(store.entitlementVerifiedThisSession, "a cached expiry is never verified")

        await store.load()   // ends with refreshEntitlements()

        XCTAssertTrue(store.entitlementVerifiedThisSession)
        XCTAssertEqual(store.plusRenewalState, .active)
        XCTAssertTrue(store.isWithinPlusGrace)
    }

    func testEntitlementStaysUnverifiedWhenStoreKitCannotAnswer() async throws {
        let offline = StoreKitError.networkError(URLError(.notConnectedToInternet))
        try await session.setSimulatedError(.generic(offline), forAPI: .subscriptionStatus)
        try await session.setSimulatedError(.generic(offline), forAPI: .loadProducts)
        let store = makeStore()

        await store.refreshEntitlements()

        XCTAssertFalse(store.entitlementVerifiedThisSession, "offline: nothing is verified, so nothing is removed")
        XCTAssertNil(store.plusRenewalState)
        try await session.setSimulatedError(nil, forAPI: .subscriptionStatus)
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
    }

    // MARK: Promoted In-App Purchases (App Store product page)

    /// A `PurchaseIntent` cannot be made in a test, so the decision it feeds is pinned on its own: the paywall
    /// opens with the promoted plan selected, the Day Pass card for the pass, and nothing for anything else.
    func testPromotedPurchaseSelectsThePaywallPlan() {
        XCTAssertEqual(PurchaseStore.promotedPurchase(for: PurchaseStore.ProductID.yearly, isPlus: false), .plus(yearly: true))
        XCTAssertEqual(PurchaseStore.promotedPurchase(for: PurchaseStore.ProductID.monthly, isPlus: false), .plus(yearly: false))
        XCTAssertEqual(PurchaseStore.promotedPurchase(for: PurchaseStore.ProductID.dayPass, isPlus: false), .dayPass)
        XCTAssertNil(PurchaseStore.promotedPurchase(for: "beta.Rhythm.plus.lifetime", isPlus: false), "not sold by the paywall")
        XCTAssertNil(PurchaseStore.promotedPurchase(for: "", isPlus: false))
    }

    func testPromotedPurchaseIsDroppedWhilePlusIsActive() {
        for id in PurchaseStore.ProductID.all {
            XCTAssertNil(PurchaseStore.promotedPurchase(for: id, isPlus: true), "\(id): Plus is active, nothing to sell")
        }
    }

    func testPendingPromotedPurchaseIsHeldUntilTakenAndNeverBuys() async throws {
        let store = makeStore()
        XCTAssertNil(store.pendingPromotedProduct, "nothing pending at launch")
        await store.loadProducts()
        let monthly = try XCTUnwrap(store.monthly)

        // What the intents listener records: the request waits (over the splash or onboarding) as the product.
        store.pendingPromotedProduct = monthly
        XCTAssertEqual(store.pendingPromotedProduct?.id, PurchaseStore.ProductID.monthly)
        XCTAssertFalse(store.isPaywallPresented, "the paywall is AppEntry's to open, once the main UI is up")
        XCTAssertEqual(session.allTransactions().count, 0, "a promoted purchase never buys by itself")

        // AppEntry takes it: cleared, decided, and the paywall opened for the user to confirm.
        let promoted = PurchaseStore.promotedPurchase(for: monthly.id, isPlus: store.isPlus)
        store.pendingPromotedProduct = nil
        XCTAssertEqual(promoted, .plus(yearly: false))
        XCTAssertNil(store.pendingPromotedProduct)
        XCTAssertEqual(session.allTransactions().count, 0)
    }

    // MARK: Transaction.updates

    func testUpdatesListenerAppliesPurchaseMadeWhileRunning() async throws {
        let store = makeStore(listensForUpdates: true)
        await store.load()
        XCTAssertFalse(store.hasDayPass)

        _ = try await session.buyProduct(identifier: PurchaseStore.ProductID.dayPass)   // the live listener finishes it
        await waitUntil { store.hasDayPass }
        XCTAssertTrue(store.hasDayPass, "Transaction.updates delivered the pass")
        XCTAssertEqual(store.entitlement.dayPassExpiry, Entitlement.dayPassExpiry(purchasedAt: clock, calendar: .current))
        await waitUntil { Entitlement.load(from: self.defaults).dayPassExpiry != nil }
        await waitUntil { await self.unfinishedCount() == 0 }
        let unfinished = await unfinishedCount()
        XCTAssertEqual(unfinished, 0)
    }
}
