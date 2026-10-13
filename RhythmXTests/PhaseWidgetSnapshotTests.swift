import XCTest
@testable import RhythmX

final class PhaseWidgetSnapshotTests: XCTestCase {
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: anchor)! }

    func testActiveCycle() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        let s = PhaseWidgetSnapshot.make(events: events, archived: [], today: day(13))
        XCTAssertEqual(s.cycleDay, 14)
        XCTAssertEqual(s.phase, events.first { $0.date.startOfDay == day(13).startOfDay }?.eventType)
        XCTAssertEqual(s.daysUntilNext, 15)
        XCTAssertTrue(s.isActive)
    }

    func testNoDataIsEmpty() {
        let s = PhaseWidgetSnapshot.make(events: [], archived: [], today: anchor)
        XCTAssertEqual(s, PhaseWidgetSnapshot(phase: nil, cycleDay: nil, daysUntilNext: nil))
        XCTAssertFalse(s.isActive)
    }

    func testGapDayKeepsDayButNoPhase() {
        var events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        events.removeAll { $0.date.startOfDay == day(13).startOfDay }
        let s = PhaseWidgetSnapshot.make(events: events, archived: [], today: day(13))
        XCTAssertEqual(s.cycleDay, 14)
        XCTAssertNil(s.phase)
    }

    func testOverdueHidesCountdown() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        let s = PhaseWidgetSnapshot.make(events: events, archived: [], today: day(40))
        XCTAssertNil(s.daysUntilNext)
        XCTAssertEqual(s.overdueDays, 12)   // next = day(28)
        XCTAssertFalse(s.isActive)
    }

    func testNotOverdueHasNoOverdueDays() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        XCTAssertNil(PhaseWidgetSnapshot.make(events: events, archived: [], today: day(13)).overdueDays)
        XCTAssertNil(PhaseWidgetSnapshot.make(events: [], archived: [], today: anchor).overdueDays)
    }

    func testDueTodayIsNotActiveWithZeroDays() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        let s = PhaseWidgetSnapshot.make(events: events, archived: [], today: day(28))
        XCTAssertEqual(s.daysUntilNext, 0)
        XCTAssertFalse(s.isActive)
    }

    func testLoadFromDefaultsAndCorruptData() {
        let suite = "test.snapshot"
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        let d = UserDefaults(suiteName: suite)!
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        d.set(try! JSONEncoder().encode(events), forKey: PersistenceKeys.events)
        XCTAssertEqual(PhaseWidgetSnapshot.load(defaults: d, today: day(13)).cycleDay, 14)

        d.set(Data("not json".utf8), forKey: PersistenceKeys.events)
        XCTAssertFalse(PhaseWidgetSnapshot.load(defaults: d, today: day(13)).isActive)
    }

    func testTimelineHasOneEntryPerDayAndAdvances() {
        let suite = "test.timeline"
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        let d = UserDefaults(suiteName: suite)!
        d.set(try! JSONEncoder().encode(CycleGenerator.events(startDate: anchor, cycleLength: 28)), forKey: PersistenceKeys.events)

        let entries = PhaseWidgetSnapshot.timeline(defaults: d, from: day(13), days: 3)

        XCTAssertEqual(entries.map(\.snapshot.cycleDay), [14, 15, 16])
        XCTAssertEqual(entries[0].date, day(13))
        XCTAssertEqual(entries[1].date, day(14).startOfDay)
        XCTAssertEqual(entries[2].date, day(15).startOfDay)
    }
}
