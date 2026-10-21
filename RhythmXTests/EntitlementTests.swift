import XCTest
@testable import RhythmX

/// Pure entitlement rules (Review Focus 4 and 5). No StoreKit here.
final class EntitlementTests: XCTestCase {
    private let suiteName = "test.entitlement"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // MARK: Review Focus 4: Day Pass bought at 11:58 pm ends at midnight

    func testDayPassExpiresAtStartOfNextLocalDay() {
        let ny = calendar("America/New_York")
        let purchase = date(2026, 10, 19, 23, 58, in: ny)
        let expiry = Entitlement.dayPassExpiry(purchasedAt: purchase, calendar: ny)

        XCTAssertEqual(expiry, date(2026, 10, 20, 0, 0, in: ny), "expires at the start of the next local day")
        XCTAssertEqual(expiry.timeIntervalSince(purchase), 120, "two minutes of pass, not 24 hours")

        let e = Entitlement(plusExpiry: nil, dayPassExpiry: expiry)
        XCTAssertTrue(e.hasDayPass(now: purchase))
        XCTAssertTrue(e.hasDayPass(now: expiry.addingTimeInterval(-1)))
        XCTAssertFalse(e.hasDayPass(now: expiry), "midnight itself is already expired")
        XCTAssertTrue(e.canExportPDF(now: purchase))
        XCTAssertFalse(e.canExportPDF(now: expiry))
        XCTAssertFalse(e.isPlus(now: purchase), "a day pass is not Plus")
    }

    func testDayPassBoughtAtMidnightLastsTheWholeDay() {
        let ny = calendar("America/New_York")
        let purchase = date(2026, 10, 20, 0, 0, in: ny)
        XCTAssertEqual(Entitlement.dayPassExpiry(purchasedAt: purchase, calendar: ny), date(2026, 10, 21, 0, 0, in: ny))
    }

    func testDayPassExpiryOnDaylightSavingChangeDay() {
        // 1 Nov 2026 is a 25-hour day in New York. The pass still ends at the next local midnight.
        let ny = calendar("America/New_York")
        let purchase = date(2026, 11, 1, 0, 30, in: ny)
        let expiry = Entitlement.dayPassExpiry(purchasedAt: purchase, calendar: ny)
        XCTAssertEqual(expiry, date(2026, 11, 2, 0, 0, in: ny))
        XCTAssertEqual(expiry.timeIntervalSince(ny.startOfDay(for: purchase)), 25 * 3600)
    }

    // MARK: Review Focus 4: time zone or clock change must not extend the pass

    func testDayPassExpiryIsAbsoluteAcrossTimeZoneChange() {
        let ny = calendar("America/New_York")
        let tokyo = calendar("Asia/Tokyo")
        let purchase = date(2026, 10, 19, 23, 58, in: ny)
        let expiry = Entitlement.dayPassExpiry(purchasedAt: purchase, calendar: ny)

        // Stored as an absolute instant, read back unchanged.
        Entitlement(plusExpiry: nil, dayPassExpiry: expiry).save(to: defaults)
        let loaded = Entitlement.load(from: defaults)
        XCTAssertEqual(loaded.dayPassExpiry, expiry)

        // The phone now sits in Tokyo, where that instant is 13:00 on 20 Oct and the "local day" would run
        // another 11 hours. The stored instant is not recomputed from the new calendar.
        let tokyoDayEnd = Entitlement.dayPassExpiry(purchasedAt: expiry, calendar: tokyo)
        XCTAssertGreaterThan(tokyoDayEnd, expiry)
        XCTAssertEqual(tokyo.component(.hour, from: expiry), 13)
        XCTAssertTrue(loaded.hasDayPass(now: expiry.addingTimeInterval(-60)))
        XCTAssertFalse(loaded.hasDayPass(now: expiry))
        XCTAssertFalse(loaded.hasDayPass(now: expiry.addingTimeInterval(3600)))
        XCTAssertFalse(loaded.hasDayPass(now: tokyoDayEnd.addingTimeInterval(-1)), "Tokyo's later midnight grants nothing")

        // Going the other way (to Honolulu, 6 hours behind New York) does not extend it either.
        let honolulu = calendar("Pacific/Honolulu")
        XCTAssertEqual(honolulu.component(.hour, from: expiry), 18)
        let honoluluDayEnd = Entitlement.dayPassExpiry(purchasedAt: expiry, calendar: honolulu)
        XCTAssertGreaterThan(honoluluDayEnd, expiry)
        XCTAssertFalse(loaded.hasDayPass(now: expiry.addingTimeInterval(1)))
    }

    func testDayPassExpiryIsNeverExtendedByALaterSave() {
        // Re-saving the same entitlement (for example after a refresh on launch) keeps the instant; nothing
        // recomputes it from "today".
        let ny = calendar("America/New_York")
        let expiry = Entitlement.dayPassExpiry(purchasedAt: date(2026, 10, 19, 23, 58, in: ny), calendar: ny)
        var e = Entitlement(plusExpiry: nil, dayPassExpiry: expiry)
        e.save(to: defaults)
        e = Entitlement.load(from: defaults)
        e.save(to: defaults)
        XCTAssertEqual(Entitlement.load(from: defaults).dayPassExpiry, expiry)
    }

    // MARK: Review Focus 5: Plus grace for lapsed or offline devices

    func testPlusGraceThreeDays() {
        let expiry = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let e = Entitlement(plusExpiry: expiry, dayPassExpiry: nil)
        let day: TimeInterval = 86_400

        XCTAssertTrue(e.isPlus(now: expiry.addingTimeInterval(-1)))
        XCTAssertTrue(e.isPlus(now: expiry.addingTimeInterval(2 * day)), "still Plus two days after expiry (grace)")
        XCTAssertTrue(e.isPlus(now: expiry.addingTimeInterval(3 * day - 1)))
        XCTAssertFalse(e.isPlus(now: expiry.addingTimeInterval(3 * day)))
        XCTAssertFalse(e.isPlus(now: expiry.addingTimeInterval(3 * day + 1)), "grace is over after three days")

        XCTAssertTrue(e.canExportPDF(now: expiry.addingTimeInterval(-1)))
        XCTAssertFalse(e.canExportPDF(now: expiry), "no grace for exports")
        XCTAssertFalse(e.canExportPDF(now: expiry.addingTimeInterval(day)))

        XCTAssertEqual(Entitlement.plusGrace, 3 * day)
        XCTAssertFalse(e.isPlus(now: expiry.addingTimeInterval(1), grace: 0), "grace can be switched off")
    }

    func testPlusWinsOverDayPass() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let activePlus = now.addingTimeInterval(30 * 86_400)
        let expiredPass = now.addingTimeInterval(-60)

        let plusOnly = Entitlement(plusExpiry: activePlus, dayPassExpiry: expiredPass)
        XCTAssertTrue(plusOnly.isPlus(now: now))
        XCTAssertFalse(plusOnly.hasDayPass(now: now))
        XCTAssertTrue(plusOnly.canExportPDF(now: now), "Plus exports without a day pass")

        let both = Entitlement(plusExpiry: activePlus, dayPassExpiry: now.addingTimeInterval(60))
        XCTAssertTrue(both.canExportPDF(now: now))

        let passOnly = Entitlement(plusExpiry: now.addingTimeInterval(-10 * 86_400), dayPassExpiry: now.addingTimeInterval(60))
        XCTAssertFalse(passOnly.isPlus(now: now))
        XCTAssertTrue(passOnly.hasDayPass(now: now))
        XCTAssertTrue(passOnly.canExportPDF(now: now), "a day pass exports without Plus")
    }

    // MARK: Persistence contract (widgets read the same keys)

    func testEmptyDefaultsMeansNoEntitlement() {
        let e = Entitlement.load(from: defaults)
        XCTAssertEqual(e, Entitlement(plusExpiry: nil, dayPassExpiry: nil))
        XCTAssertEqual(e, .none)
        let now = Date()
        XCTAssertFalse(e.isPlus(now: now))
        XCTAssertFalse(e.hasDayPass(now: now))
        XCTAssertFalse(e.canExportPDF(now: now))
    }

    func testPersistenceKeysAndDateRoundTrip() {
        XCTAssertEqual(PersistenceKeys.plusExpiry, "com.example.rhythm(x).plusExpiry")
        XCTAssertEqual(PersistenceKeys.dayPassExpiry, "com.example.rhythm(x).dayPassExpiry")

        let plus = Date(timeIntervalSinceReferenceDate: 800_000_000.25)
        let pass = Date(timeIntervalSinceReferenceDate: 800_001_000.5)
        Entitlement(plusExpiry: plus, dayPassExpiry: pass).save(to: defaults)
        XCTAssertEqual(defaults.object(forKey: PersistenceKeys.plusExpiry) as? Date, plus)
        XCTAssertEqual(defaults.object(forKey: PersistenceKeys.dayPassExpiry) as? Date, pass)
        XCTAssertEqual(Entitlement.load(from: defaults), Entitlement(plusExpiry: plus, dayPassExpiry: pass))

        // Saving nil removes the key, so a lapsed value cannot linger under a stale date.
        Entitlement(plusExpiry: nil, dayPassExpiry: pass).save(to: defaults)
        XCTAssertNil(defaults.object(forKey: PersistenceKeys.plusExpiry))
        XCTAssertEqual(Entitlement.load(from: defaults).dayPassExpiry, pass)
    }
}
