import XCTest
@testable import RhythmX

/// Task 15: the export gate in front of the two PDFs. Preview is always free; export needs Plus (no grace) or a
/// running Day Pass. The Day Pass copy is pinned because the user and App Review read it.
final class ExportGateTests: XCTestCase {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 15))!

    func testGateLockedWithoutPlusOrPass() {
        XCTAssertEqual(ExportGate.state(.none, now: now), .locked)
        XCTAssertFalse(ExportGate.state(.none, now: now).isUnlocked)
    }

    func testGateUnlockedWithPass() {
        let expiry = Entitlement.dayPassExpiry(purchasedAt: now)
        let entitlement = Entitlement(plusExpiry: nil, dayPassExpiry: expiry)
        XCTAssertEqual(ExportGate.state(entitlement, now: now), .unlocked(until: expiry))
        XCTAssertEqual(ExportGate.state(entitlement, now: expiry.addingTimeInterval(-1)), .unlocked(until: expiry),
                       "one second before midnight the pass still runs")
        XCTAssertEqual(ExportGate.state(entitlement, now: expiry), .locked, "at midnight it is over")
    }

    func testGateLockedAfterPassExpiryEvenWithinGrace() {
        let expired = Entitlement(plusExpiry: nil, dayPassExpiry: now.addingTimeInterval(-60))
        XCTAssertEqual(ExportGate.state(expired, now: now), .locked)

        // A lapsed Plus period is still inside the 3-day grace the widgets honor; exports do not get it.
        let lapsed = Entitlement(plusExpiry: now.addingTimeInterval(-3600), dayPassExpiry: nil)
        XCTAssertTrue(lapsed.isPlus(now: now), "inside the widget grace")
        XCTAssertEqual(ExportGate.state(lapsed, now: now), .locked, "grace applies to widgets only")

        let lapsedWithOldPass = Entitlement(plusExpiry: now.addingTimeInterval(-3600), dayPassExpiry: now.addingTimeInterval(-7200))
        XCTAssertEqual(ExportGate.state(lapsedWithOldPass, now: now), .locked)
    }

    func testPlusAlwaysUnlocked() {
        let plus = Entitlement(plusExpiry: now.addingTimeInterval(30 * 86_400), dayPassExpiry: nil)
        XCTAssertEqual(ExportGate.state(plus, now: now), .unlocked(until: nil))
        XCTAssertTrue(ExportGate.state(plus, now: now).isUnlocked)

        // Plus wins over a running pass: no end time is shown.
        let both = Entitlement(plusExpiry: now.addingTimeInterval(30 * 86_400), dayPassExpiry: Entitlement.dayPassExpiry(purchasedAt: now))
        XCTAssertEqual(ExportGate.state(both, now: now), .unlocked(until: nil))

        // Plus that ends later today still exports now, without grace.
        let endingSoon = Entitlement(plusExpiry: now.addingTimeInterval(60), dayPassExpiry: nil)
        XCTAssertEqual(ExportGate.state(endingSoon, now: now), .unlocked(until: nil))
        XCTAssertEqual(ExportGate.state(endingSoon, now: now.addingTimeInterval(61)), .locked)
    }

    // MARK: - Copy

    func testDayPassCopyExact() {
        XCTAssertEqual(ExportCopy.dayPassTitle(price: "$0.99"), "Day Pass · $0.99")
        XCTAssertEqual(ExportCopy.dayPassBody,
                       "Unlocks the calendar and the report, any month, until midnight tonight. Plus members export free.")
        XCTAssertEqual(ExportCopy.unlockedWithPlus, "Unlocked with RhythmX Plus")
        XCTAssertFalse(ExportCopy.dayPassBody.contains("—"), "plain copy, no em dashes")
    }

    func testUnlockedUntilNamesTheLastMinuteOfTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let purchase = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 23, minute: 58))!
        let expiry = Entitlement.dayPassExpiry(purchasedAt: purchase, calendar: calendar)
        XCTAssertEqual(ExportCopy.unlockedUntil(expiry, calendar: calendar, locale: Locale(identifier: "en_US")),
                       "Unlocked until 11:59 pm")
        XCTAssertEqual(ExportCopy.unlockedUntil(expiry, calendar: calendar, locale: Locale(identifier: "en_GB")),
                       "Unlocked until 23:59")
    }
}
