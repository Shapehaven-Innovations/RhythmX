//  Entitlement.swift
//
//  Pure entitlement rules shared by the app and the widget extension. No StoreKit import: the widget gates
//  on the dates the app caches in `AppGroup.defaults` without talking to the store.

import Foundation

/// The subscription's renewal state as StoreKit last reported it this session (no StoreKit types here).
enum PlusRenewalState: Equatable {
    case active
    /// The App Store's billing grace period: Plus stays on while payment is retried.
    case inGracePeriod
    /// Payment failed and the App Store is still retrying.
    case inBillingRetry
    /// Expired or revoked, or no subscription at all.
    case expired
}

struct Entitlement: Equatable {
    /// Widgets and an offline app keep Plus for this long after the cached expiry, so a renewal that has not
    /// been confirmed yet does not flip the widgets to the upgrade prompt. Exports do not get this grace.
    static let plusGrace: TimeInterval = 3 * 86_400

    static let none = Entitlement(plusExpiry: nil, dayPassExpiry: nil)

    /// Expiry of the current or last Plus subscription period, `nil` when there never was one or it was refunded.
    var plusExpiry: Date?
    /// Absolute end of the Day Pass: the start of the next local day at purchase time (`dayPassExpiry(purchasedAt:)`).
    var dayPassExpiry: Date?

    func isPlus(now: Date, grace: TimeInterval = Entitlement.plusGrace) -> Bool {
        guard let plusExpiry else { return false }
        return now < plusExpiry.addingTimeInterval(grace)
    }

    func hasDayPass(now: Date) -> Bool {
        guard let dayPassExpiry else { return false }
        return now < dayPassExpiry
    }

    /// PDF export: Plus without grace, or a Day Pass that is still running.
    func canExportPDF(now: Date) -> Bool {
        isPlus(now: now, grace: 0) || hasDayPass(now: now)
    }

    /// The instant the Day Pass ends: midnight at the start of the next local day in `calendar`. It is stored as
    /// an absolute date, so a later time zone or calendar change does not move it.
    static func dayPassExpiry(purchasedAt: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: purchasedAt)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// Whether a lapsed Plus may still come back without a new purchase: inside `plusGrace` after the cached
    /// expiry, or (when StoreKit reported it) while the App Store is still trying to renew. Destructive work
    /// that follows a lapse, such as removing the Apple Calendar events, waits until this is false.
    static func isWithinGrace(_ entitlement: Entitlement, now: Date, renewal: PlusRenewalState?) -> Bool {
        switch renewal {
        case .active?, .inGracePeriod?, .inBillingRetry?: return true
        case .expired?, nil: return entitlement.isPlus(now: now, grace: plusGrace)
        }
    }

    // MARK: Persistence (the widget reads the same keys)

    static func load(from defaults: UserDefaults) -> Entitlement {
        Entitlement(plusExpiry: defaults.object(forKey: PersistenceKeys.plusExpiry) as? Date,
                    dayPassExpiry: defaults.object(forKey: PersistenceKeys.dayPassExpiry) as? Date)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(plusExpiry, forKey: PersistenceKeys.plusExpiry)
        defaults.set(dayPassExpiry, forKey: PersistenceKeys.dayPassExpiry)
    }
}
