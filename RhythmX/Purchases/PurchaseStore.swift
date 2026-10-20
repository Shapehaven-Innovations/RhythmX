//  PurchaseStore.swift
//
//  StoreKit 2 only. No server, no account: the entitlement is evaluated on the device from
//  `Transaction.currentEntitlements` and cached as dates in `AppGroup.defaults` for the widgets.

import Foundation
import StoreKit
import UIKit

@MainActor
final class PurchaseStore: ObservableObject {
    enum ProductID {
        static let monthly = "beta.Rhythm.plus.monthly"
        static let yearly = "beta.Rhythm.plus.yearly"
        static let dayPass = "beta.Rhythm.pdf.daypass"
        static let plus: Set<String> = [monthly, yearly]
        static let all = [monthly, yearly, dayPass]
    }

    enum PurchaseOutcome: Equatable {
        case purchased
        /// Waiting for approval (Ask to Buy). `Transaction.updates` delivers the result later.
        case pending
        case cancelled
    }

    enum PurchaseError: LocalizedError {
        case productUnavailable
        case unverified

        var errorDescription: String? {
            switch self {
            case .productUnavailable: return "This item is not available right now. Please try again later."
            case .unverified: return "The App Store could not verify this purchase."
            }
        }
    }

    @Published private(set) var entitlement: Entitlement
    @Published private(set) var products: [Product] = []
    /// True once `refreshEntitlements()` has finished with an answer from the App Store this session (the
    /// subscription status could be read). A cached expiry alone, or an offline launch, never sets it.
    /// Apple Calendar removes its events after a lapse only when this is true (`CalendarSyncPolicy`).
    @Published private(set) var entitlementVerifiedThisSession = false
    /// The renewal state from that answer; nil until StoreKit has answered.
    @Published private(set) var plusRenewalState: PlusRenewalState?

    /// The one paywall sheet, presented at the root (`AppEntry`). Settings and the widget's paywall link both set
    /// this instead of presenting their own sheet, so two presenters can never collide; a second request while
    /// the sheet is already up changes nothing.
    @Published var isPaywallPresented = false

    var monthly: Product? { products.first { $0.id == ProductID.monthly } }
    var yearly: Product? { products.first { $0.id == ProductID.yearly } }
    var dayPass: Product? { products.first { $0.id == ProductID.dayPass } }

    /// Plus as the app sees it: no grace. The 3-day grace in `Entitlement.isPlus` is for the widgets, which read
    /// the cached expiry without talking to the store; the app can always refresh, so a lapsed user sees the
    /// purchase options again as soon as the period ends.
    var isPlus: Bool { entitlement.isPlus(now: now(), grace: 0) }
    /// A lapse that may still undo itself: within `Entitlement.plusGrace` of the cached expiry, or in the App
    /// Store's billing grace or retry period.
    var isWithinPlusGrace: Bool { Entitlement.isWithinGrace(entitlement, now: now(), renewal: plusRenewalState) }
    var hasDayPass: Bool { entitlement.hasDayPass(now: now()) }
    var canExportPDF: Bool { entitlement.canExportPDF(now: now()) }

    /// The store's clock (injectable in tests). Views that gate on the entitlement read the time from here.
    func currentDate() -> Date { now() }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private var updatesTask: Task<Void, Never>?

    /// - Parameters:
    ///   - listensForUpdates: starts the `Transaction.updates` listener for the lifetime of the store. Off in tests
    ///     that drive the queue by hand.
    init(defaults: UserDefaults = AppGroup.defaults,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init,
         listensForUpdates: Bool = true) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        entitlement = Entitlement.load(from: defaults)
        if listensForUpdates {
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    await self.handle(result)
                }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: Launch

    /// Loads the products, applies any purchase the app did not get to finish, then refreshes Plus.
    func load() async {
        await loadProducts()
        await processUnfinished()
        await refreshEntitlements()
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = ProductID.all.compactMap { id in loaded.first { $0.id == id } }
        } catch {
            products = []
        }
    }

    // MARK: Purchases

    @discardableResult
    func purchasePlus(yearly: Bool) async throws -> PurchaseOutcome {
        try await purchase(yearly ? ProductID.yearly : ProductID.monthly)
    }

    @discardableResult
    func purchaseDayPass() async throws -> PurchaseOutcome {
        try await purchase(ProductID.dayPass)
    }

    private func purchase(_ id: String) async throws -> PurchaseOutcome {
        if products.isEmpty { await loadProducts() }
        guard let product = products.first(where: { $0.id == id }) else { throw PurchaseError.productUnavailable }
        let result: Product.PurchaseResult
        if let scene = Self.activeScene {
            result = try await product.purchase(confirmIn: scene)
        } else {
            result = try await product.purchase()
        }
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw PurchaseError.unverified }
            await apply(transaction)
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Restore Purchases. Subscriptions come back through `currentEntitlements`; a consumed Day Pass does not,
    /// and an expired one is never revived (its stored expiry stays in the past).
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            // Cancelled sign-in or no network: the local entitlement cache still refreshes below.
        }
        await processUnfinished()
        await refreshEntitlements()
    }

    // MARK: Entitlements

    /// Recomputes the Plus expiry from StoreKit and caches it. A lapsed subscription keeps its last expiry so
    /// the widgets can apply the grace period; a refunded one is cleared.
    func refreshEntitlements() async {
        var expiry: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProductID.plus.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            expiry = max(expiry ?? .distantPast, transaction.expirationDate ?? .distantFuture)
        }
        if expiry == nil {
            for id in ProductID.plus {
                guard let latest = await Transaction.latest(for: id),
                      case .verified(let transaction) = latest,
                      transaction.revocationDate == nil,
                      let expirationDate = transaction.expirationDate else { continue }
                expiry = max(expiry ?? .distantPast, expirationDate)
            }
        }
        var updated = Entitlement.load(from: defaults)   // keeps a Day Pass written by another instance
        updated.plusExpiry = expiry
        commit(updated)
        // The renewal state first, so anything watching both sees it once verification is set.
        if let renewal = await fetchRenewalState() {
            plusRenewalState = renewal
            entitlementVerifiedThisSession = true
        }
    }

    /// The Plus renewal state from the App Store, or nil when StoreKit could not answer (offline, products not
    /// loaded). `currentEntitlements` answers from the device cache even offline, so this network-backed call is
    /// what counts as StoreKit having answered.
    private func fetchRenewalState() async -> PlusRenewalState? {
        if products.isEmpty { await loadProducts() }
        guard let groupID = (yearly ?? monthly)?.subscription?.subscriptionGroupID else { return nil }
        let statuses: [Product.SubscriptionInfo.Status]
        do {
            statuses = try await Product.SubscriptionInfo.status(for: groupID)
        } catch {
            return nil
        }
        let states = statuses.map(\.state)
        if states.contains(.subscribed) { return .active }
        if states.contains(.inGracePeriod) { return .inGracePeriod }
        if states.contains(.inBillingRetryPeriod) { return .inBillingRetry }
        return .expired
    }

    private func processUnfinished() async {
        for await result in Transaction.unfinished {
            await handle(result)
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        // An unverified transaction grants nothing and stays unfinished, so StoreKit presents it again later.
        guard case .verified(let transaction) = result else { return }
        await apply(transaction)
    }

    /// One path for a fresh purchase, an unfinished transaction found at launch, and `Transaction.updates`.
    private func apply(_ transaction: Transaction) async {
        if transaction.productID == ProductID.dayPass {
            if transaction.revocationDate == nil {
                await grantDayPass(transactionID: transaction.id, purchaseDate: transaction.purchaseDate) {
                    await transaction.finish()
                }
            } else {
                await transaction.finish()
            }
        } else if ProductID.plus.contains(transaction.productID) {
            await refreshEntitlements()
            await transaction.finish()
        } else {
            await transaction.finish()
        }
    }

    /// Records the Day Pass, then calls `finish`. The pass is the local day of `purchaseDate` (the date StoreKit
    /// recorded), so a transaction recovered later does not start a new day; one recovered after that day has
    /// ended grants nothing. A pass already running is never shortened (the later expiry wins). The expiry is on
    /// disk before the transaction is finished, so an app that dies in between sees the transaction again at
    /// launch and this method runs once more: the transaction id is already recorded, nothing is granted twice
    /// and nothing is extended. Returns whether a pass was newly granted.
    @discardableResult
    func grantDayPass(transactionID: UInt64, purchaseDate: Date, finish: () async -> Void) async -> Bool {
        let key = PersistenceKeys.dayPassTransactions
        var applied = defaults.stringArray(forKey: key) ?? []
        let id = String(transactionID)
        var granted = false
        if !applied.contains(id) {
            applied.append(id)
            if applied.count > 100 { applied.removeFirst(applied.count - 100) }
            defaults.set(applied, forKey: key)
            let expiry = Entitlement.dayPassExpiry(purchasedAt: purchaseDate, calendar: calendar)
            if expiry > now() {
                var updated = Entitlement.load(from: defaults)
                updated.dayPassExpiry = max(updated.dayPassExpiry ?? .distantPast, expiry)
                commit(updated)
                granted = true
            }
        }
        await finish()
        return granted
    }

    private func commit(_ updated: Entitlement) {
        let changed = updated != entitlement || updated != Entitlement.load(from: defaults)
        updated.save(to: defaults)
        entitlement = updated
        if changed { AppGroup.reloadWidgets() }
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
