import XCTest
@testable import RhythmX

/// Task 17: Week Strip widget data and its Plus gate (Review Focus 2 and 5).
final class WeekStripSnapshotTests: XCTestCase {
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: anchor)! }

    private func weekStart(of date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)!.start
    }

    // MARK: - Days

    func testSevenDaysStartingAtWeekStart() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        let today = day(10)
        let days = PhaseWidgetSnapshot.weekDays(events: events, today: today)

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.date, weekStart(of: today))
        for (i, d) in days.enumerated() {
            XCTAssertEqual(d.date, Calendar.current.date(byAdding: .day, value: i, to: weekStart(of: today)))
            XCTAssertEqual(d.date, d.date.startOfDay, "dates are day starts")
            let expected = events.first { $0.date.startOfDay == d.date }?.eventType
            XCTAssertEqual(d.phase, expected, "day \(i) carries that day's phase")
        }
        // Today is in the strip whatever weekday it is.
        for offset in 0..<7 {
            let strip = PhaseWidgetSnapshot.weekDays(events: events, today: day(offset))
            XCTAssertEqual(strip.count, 7)
            XCTAssertTrue(strip.contains { $0.date == day(offset).startOfDay })
            XCTAssertLessThanOrEqual(strip.first!.date, day(offset).startOfDay)
            XCTAssertGreaterThanOrEqual(strip.last!.date, day(offset).startOfDay)
        }
    }

    func testEmptyDaysHaveNoPhase() {
        let days = PhaseWidgetSnapshot.weekDays(events: [], today: day(3))
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days.allSatisfy { $0.phase == nil })
        XCTAssertEqual(days.filter(\.isToday).count, 1)
    }

    /// Review Focus 2: menopause events never feed the Week Strip.
    func testMenopauseEventsIgnored() {
        let today = day(10)
        let start = weekStart(of: today)
        var events: [Event] = []
        for i in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: i, to: start)!
            events.append(Event(eventType: .menstrual, date: date, note: "", tags: "Menopause:Hot Flashes", mode: .menopause))
        }
        let onlyMenopause = PhaseWidgetSnapshot.weekDays(events: events, today: today)
        XCTAssertTrue(onlyMenopause.allSatisfy { $0.phase == nil }, "carrier events carry no phase")

        // A cycle event (legacy nil mode, and an explicit planning one) on two of the days does count.
        events.append(Event(eventType: .ovulation, date: Calendar.current.date(byAdding: .day, value: 2, to: start)!, note: ""))
        events.append(Event(eventType: .luteal, date: Calendar.current.date(byAdding: .day, value: 4, to: start)!, note: "", mode: .planning))
        let mixed = PhaseWidgetSnapshot.weekDays(events: events, today: today)
        XCTAssertEqual(mixed.map(\.phase), [nil, nil, .ovulation, nil, .luteal, nil, nil])
    }

    func testTodayFlagged() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        let today = day(12).addingTimeInterval(13 * 3600 + 7 * 60)   // mid-afternoon, not midnight
        let days = PhaseWidgetSnapshot.weekDays(events: events, today: today)
        XCTAssertEqual(days.filter(\.isToday).count, 1)
        XCTAssertEqual(days.first(where: \.isToday)?.date, today.startOfDay)
        XCTAssertTrue(days.filter { !$0.isToday }.allSatisfy { $0.date != today.startOfDay })
    }

    // MARK: - Plus gate (Review Focus 5)

    func testLapsedEntitlementSelectsLockedState() {
        let expiry = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let day: TimeInterval = 86_400
        let e = Entitlement(plusExpiry: expiry, dayPassExpiry: nil)

        XCTAssertEqual(WeekStripWidgetState.make(entitlement: e, now: expiry.addingTimeInterval(-day)), .unlocked)
        XCTAssertEqual(WeekStripWidgetState.make(entitlement: e, now: expiry.addingTimeInterval(2 * day)), .unlocked,
                       "the widget keeps Plus through the 3-day grace")
        XCTAssertEqual(WeekStripWidgetState.make(entitlement: e, now: expiry.addingTimeInterval(3 * day - 1)), .unlocked)
        XCTAssertEqual(WeekStripWidgetState.make(entitlement: e, now: expiry.addingTimeInterval(3 * day)), .locked,
                       "expiry plus three days: upgrade prompt, never stale Plus content")
        XCTAssertEqual(WeekStripWidgetState.make(entitlement: e, now: expiry.addingTimeInterval(400 * day)), .locked)

        XCTAssertEqual(WeekStripWidgetState.make(entitlement: .none, now: expiry), .locked, "never subscribed")
        let passOnly = Entitlement(plusExpiry: nil, dayPassExpiry: expiry.addingTimeInterval(day))
        XCTAssertEqual(WeekStripWidgetState.make(entitlement: passOnly, now: expiry), .locked, "a Day Pass is not Plus")

        // The instant the widget must flip, so a timeline can carry an entry exactly there.
        XCTAssertEqual(WeekStripWidgetState.lockDate(entitlement: e), expiry.addingTimeInterval(3 * day))
        XCTAssertNil(WeekStripWidgetState.lockDate(entitlement: .none))
    }

    /// The entries the Week Strip and Quick Log providers build: the one at expiry plus grace is `.locked` and
    /// every earlier one is `.unlocked`, so a lapsed or offline device flips without waiting for a reload.
    func testTimelineEntriesFlipToLockedAtExpiryPlusGrace() {
        let now = day(10).addingTimeInterval(10 * 3600)
        let expiry = day(8).addingTimeInterval(14 * 3600)
        let lock = expiry.addingTimeInterval(Entitlement.plusGrace)   // day 11, 14:00
        let e = Entitlement(plusExpiry: expiry, dayPassExpiry: nil)

        // Week Strip: now plus the next six day starts, horizon a week out.
        let weekBase = (0..<7).map { $0 == 0 ? now : now.startOfDay.diff(numDays: $0) }
        let week = PlusWidgetState.timeline(base: weekBase, now: now, horizon: now.startOfDay.diff(numDays: 7), entitlement: e)
        XCTAssertEqual(week.count, 8, "the lock instant is an entry of its own")
        XCTAssertEqual(week.map(\.date), week.map(\.date).sorted())
        XCTAssertEqual(week.map(\.state), week.map { $0.date < lock ? PlusWidgetState.unlocked : .locked })
        XCTAssertEqual(week.first { $0.state == .locked }?.date, lock, "locked exactly at expiry plus grace, not before")
        XCTAssertEqual(week.filter { $0.state == .unlocked }.count, 2)

        // Quick Log: now and midnight; here the lock lands inside today.
        let midnight = now.startOfDay.diff(numDays: 1)
        let soon = Entitlement(plusExpiry: now.addingTimeInterval(3600 - Entitlement.plusGrace), dayPassExpiry: nil)
        let quick = PlusWidgetState.timeline(base: [now, midnight], now: now, horizon: midnight, entitlement: soon)
        XCTAssertEqual(quick.map(\.date), [now, now.addingTimeInterval(3600), midnight])
        XCTAssertEqual(quick.map(\.state), [.unlocked, .locked, .locked])

        // A lock outside the window adds no entry; the states still follow the dates.
        func states(_ entitlement: Entitlement) -> [PlusWidgetState] {
            PlusWidgetState.timeline(base: [now, midnight], now: now, horizon: midnight, entitlement: entitlement).map(\.state)
        }
        XCTAssertEqual(states(Entitlement(plusExpiry: day(30), dayPassExpiry: nil)), [.unlocked, .unlocked])
        XCTAssertEqual(states(Entitlement(plusExpiry: day(1), dayPassExpiry: nil)), [.locked, .locked], "already past the grace")
        XCTAssertEqual(states(.none), [.locked, .locked], "never subscribed")
        XCTAssertEqual(states(Entitlement(plusExpiry: nil, dayPassExpiry: day(30))), [.locked, .locked], "a Day Pass is not Plus")
        // A lock exactly on an existing entry or on the horizon is not doubled.
        XCTAssertEqual(states(Entitlement(plusExpiry: midnight.addingTimeInterval(-Entitlement.plusGrace), dayPassExpiry: nil)), [.unlocked, .locked])
    }

    /// The widget's paywall link waits for onboarding and drives the one shared presentation flag.
    @MainActor
    func testPaywallLinkWaitsForOnboardingAndUsesOneFlag() {
        XCTAssertTrue(AppEntry.opensPaywall(PlusWidgetState.paywallURL, onboardingFinished: true))
        XCTAssertFalse(AppEntry.opensPaywall(PlusWidgetState.paywallURL, onboardingFinished: false), "ignored until onboarding is done")
        XCTAssertFalse(AppEntry.opensPaywall(URL(string: "rhythmx://settings")!, onboardingFinished: true))
        XCTAssertFalse(AppEntry.opensPaywall(URL(fileURLWithPath: "/tmp/backup.rhythmx"), onboardingFinished: true))

        let suite = "test.weekstrip.paywall"
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        let store = PurchaseStore(defaults: UserDefaults(suiteName: suite)!, listensForUpdates: false)
        XCTAssertFalse(store.isPaywallPresented, "off until the link or Settings turns it on")
        store.isPaywallPresented = true
        XCTAssertTrue(store.isPaywallPresented)
    }

    func testPaywallDeepLink() {
        XCTAssertEqual(PlusWidgetState.paywallURL.absoluteString, "rhythmx://paywall")
        XCTAssertTrue(PlusWidgetState.isPaywallLink(PlusWidgetState.paywallURL))
        XCTAssertTrue(PlusWidgetState.isPaywallLink(URL(string: "RhythmX://Paywall")!), "scheme and host are case-insensitive")
        XCTAssertFalse(PlusWidgetState.isPaywallLink(URL(string: "rhythmx://settings")!))
        XCTAssertFalse(PlusWidgetState.isPaywallLink(URL(fileURLWithPath: "/tmp/backup.rhythmx")))
        XCTAssertFalse(PlusWidgetState.isPaywallLink(URL(string: "https://example.com/paywall")!))
    }
}
