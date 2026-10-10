import XCTest
@testable import RhythmX

final class CycleGeneratorTests: XCTestCase {
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!

    func testDayCountsFor28() {
        let c = CycleGenerator.dayCounts(cycleLength: 28)
        XCTAssertEqual(c[.menstrual], 5)
        XCTAssertEqual(c[.follicular], 8)
        XCTAssertEqual(c[.ovulation], 3)
        XCTAssertEqual(c[.luteal], 12)
    }

    func testDayCountsSumToLengthAtExtremes() {
        for length in [20, 28, 40] {
            let total = CycleGenerator.dayCounts(cycleLength: length).values.reduce(0, +)
            XCTAssertEqual(total, length, "length \(length)")
        }
        XCTAssertEqual(CycleGenerator.dayCounts(cycleLength: 20)[.luteal], 4)
        XCTAssertEqual(CycleGenerator.dayCounts(cycleLength: 40)[.luteal], 24)
    }

    func testEventsHaveOnePerDayInOrderWithNotes() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        XCTAssertEqual(events.count, 28)
        XCTAssertEqual(events.first?.eventType, .menstrual)
        XCTAssertEqual(events.first?.note, "Menstrual day 1")
        XCTAssertEqual(events.last?.eventType, .luteal)
        XCTAssertEqual(events.last?.note, "Luteal day 28")
        let last = Calendar.current.date(byAdding: .day, value: 27, to: anchor)!
        XCTAssertEqual(events.last?.date, last)
    }
}
