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

    // MARK: - Next phase / cycle length

    func testNextPhaseMidCycle() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        let today = day(13)
        let cur = events.first { $0.date.startOfDay == today.startOfDay }!.eventType
        let expected = events.filter { $0.date.startOfDay > today.startOfDay && $0.eventType != cur }
            .min { $0.date < $1.date }!
        let s = PhaseWidgetSnapshot.make(events: events, archived: [], today: today)
        XCTAssertEqual(s.nextPhase, expected.eventType)
        XCTAssertEqual(s.daysUntilNextPhase,
                       Calendar.current.dateComponents([.day], from: today.startOfDay, to: expected.date.startOfDay).day)
        XCTAssertEqual(s.cycleLength, 28)
        XCTAssertEqual(s.nextPeriodDate, day(28))
    }

    func testLastPhaseRollsIntoMenstrualAtPeriodDate() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        let s = PhaseWidgetSnapshot.make(events: events, archived: [], today: day(20))
        XCTAssertEqual(s.phase, .luteal)
        XCTAssertEqual(s.nextPhase, .menstrual)
        XCTAssertEqual(s.daysUntilNextPhase, 8)
        XCTAssertEqual(s.daysUntilNextPhase, s.daysUntilNext)
    }

    func testLastDayOfCycleNextPhaseIsTomorrow() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        let s = PhaseWidgetSnapshot.make(events: events, archived: [], today: day(27))
        XCTAssertEqual(s.nextPhase, .menstrual)
        XCTAssertEqual(s.daysUntilNextPhase, 1)
    }

    func testNoNextPhaseWithoutCycleDayOrWhenInactive() {
        let empty = PhaseWidgetSnapshot.make(events: [], archived: [], today: anchor)
        XCTAssertNil(empty.nextPhase); XCTAssertNil(empty.daysUntilNextPhase); XCTAssertNil(empty.cycleLength)

        var events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        events.removeAll { $0.date.startOfDay == day(13).startOfDay }   // gap day: no current phase
        let gap = PhaseWidgetSnapshot.make(events: events, archived: [], today: day(13))
        XCTAssertNil(gap.nextPhase)

        let overdue = PhaseWidgetSnapshot.make(events: CycleGenerator.events(startDate: anchor, cycleLength: 28), archived: [], today: day(40))
        XCTAssertNil(overdue.nextPhase); XCTAssertNil(overdue.cycleLength)
    }

    func testPeriodSoonThreshold() {
        XCTAssertTrue(PhaseWidgetSnapshot(phase: .luteal, cycleDay: 25, daysUntilNext: 3).isPeriodSoon)
        XCTAssertTrue(PhaseWidgetSnapshot(phase: .luteal, cycleDay: 27, daysUntilNext: 1).isPeriodSoon)
        XCTAssertFalse(PhaseWidgetSnapshot(phase: .luteal, cycleDay: 24, daysUntilNext: 4).isPeriodSoon)
        XCTAssertFalse(PhaseWidgetSnapshot(phase: nil, cycleDay: nil, daysUntilNext: nil).isPeriodSoon)
    }

    // MARK: - Fertile window

    private var cycleEvents: [Event] { CycleGenerator.events(startDate: anchor, cycleLength: 28) }

    func testInsideFertileWindow() {
        let s = PhaseWidgetSnapshot.make(events: cycleEvents, archived: [], today: day(8))
        XCTAssertTrue(s.isFertileToday)
        XCTAssertEqual(s.fertileEndsIn, 7)       // window runs through day(15)
        XCTAssertNil(s.fertileStartsIn)
    }

    func testLastFertileDayEndsToday() {
        let s = PhaseWidgetSnapshot.make(events: cycleEvents, archived: [], today: day(15))
        XCTAssertTrue(s.isFertileToday)
        XCTAssertEqual(s.fertileEndsIn, 0)
    }

    func testBeforeWindowCountsDown() {
        let s = PhaseWidgetSnapshot.make(events: cycleEvents, archived: [], today: day(5))
        XCTAssertFalse(s.isFertileToday)
        XCTAssertEqual(s.fertileStartsIn, 3)
        XCTAssertNil(s.fertileEndsIn)
    }

    func testAfterWindowHasNothingUpcoming() {
        let s = PhaseWidgetSnapshot.make(events: cycleEvents, archived: [], today: day(16))
        XCTAssertFalse(s.isFertileToday)
        XCTAssertNil(s.fertileStartsIn)
        XCTAssertNil(s.fertileEndsIn)
    }

    func testManualOverridesChangeSnapshot() {
        var o = FertileOverrides()
        o.removed = [FertileWindow.dayKey(day(8))]
        o.added = [FertileWindow.dayKey(day(20))]
        let early = PhaseWidgetSnapshot.make(events: cycleEvents, archived: [], today: day(7), fertileOverrides: o)
        XCTAssertEqual(early.fertileStartsIn, 2)                     // day 8 removed, window now starts day 9
        let late = PhaseWidgetSnapshot.make(events: cycleEvents, archived: [], today: day(16), fertileOverrides: o)
        XCTAssertEqual(late.fertileStartsIn, 4)                      // manual day(20)
    }

    func testNoDataHasNoFertileInfo() {
        let s = PhaseWidgetSnapshot.make(events: [], archived: [], today: anchor)
        XCTAssertFalse(s.isFertileToday)
        XCTAssertNil(s.fertileStartsIn); XCTAssertNil(s.fertileEndsIn)
    }
}
