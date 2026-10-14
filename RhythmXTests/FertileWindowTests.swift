import XCTest
@testable import RhythmX

final class FertileWindowTests: XCTestCase {
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: anchor)! }
    private func key(_ n: Int) -> String { FertileWindow.dayKey(day(n)) }
    private var events: [Event] { CycleGenerator.events(startDate: anchor, cycleLength: 28) }

    func testDayKeyFormat() {
        XCTAssertEqual(FertileWindow.dayKey(anchor), "2024-01-01")
    }

    func testAutoWindowIsFiveDaysBeforeThroughEndOfOvulationPhase() {
        let auto = FertileWindow.autoDays(events: events)
        XCTAssertEqual(auto.count, 8)                 // offsets 8...15 (ovulation phase is 13..15)
        XCTAssertFalse(auto.contains(key(7)))
        XCTAssertTrue(auto.contains(key(8)))
        XCTAssertTrue(auto.contains(key(15)))
        XCTAssertFalse(auto.contains(key(16)))
    }

    func testNoOvulationMeansNoAutoWindow() {
        let noOv = events.filter { $0.eventType != .ovulation }
        XCTAssertTrue(FertileWindow.autoDays(events: noOv).isEmpty)
        XCTAssertTrue(FertileWindow.autoDays(events: []).isEmpty)
    }

    func testOverridesAddAndRemove() {
        var o = FertileOverrides()
        o.added = [key(0)]
        o.removed = [key(10)]
        let days = FertileWindow.days(events: events, overrides: o)
        XCTAssertTrue(days.contains(key(0)))
        XCTAssertFalse(days.contains(key(10)))
        XCTAssertTrue(days.contains(key(9)))
    }

    func testToggleAutoDayRemovesThenRestores() {
        let auto = FertileWindow.autoDays(events: events)
        let off = FertileWindow.toggled(FertileOverrides(), date: day(10), autoDays: auto)
        XCTAssertEqual(off.removed, [key(10)])
        XCTAssertTrue(off.added.isEmpty)
        let on = FertileWindow.toggled(off, date: day(10), autoDays: auto)
        XCTAssertEqual(on, FertileOverrides())
    }

    func testToggleNonAutoDayAddsThenRemoves() {
        let auto = FertileWindow.autoDays(events: events)
        let on = FertileWindow.toggled(FertileOverrides(), date: day(2), autoDays: auto)
        XCTAssertEqual(on.added, [key(2)])
        let off = FertileWindow.toggled(on, date: day(2), autoDays: auto)
        XCTAssertEqual(off, FertileOverrides())
    }

    func testSaveLoadRoundTripAndCorruptData() {
        let suite = "test.fertile"
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        let d = UserDefaults(suiteName: suite)!
        XCTAssertEqual(FertileWindow.loadOverrides(from: d), FertileOverrides())

        var o = FertileOverrides(); o.added = ["2024-01-02"]; o.removed = ["2024-01-10"]
        FertileWindow.saveOverrides(o, to: d)
        XCTAssertEqual(FertileWindow.loadOverrides(from: d), o)

        d.set(Data("garbage".utf8), forKey: FertileWindow.overridesKey)
        XCTAssertEqual(FertileWindow.loadOverrides(from: d), FertileOverrides())
    }
}
