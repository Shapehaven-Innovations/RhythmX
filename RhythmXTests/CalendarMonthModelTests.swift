import XCTest
@testable import RhythmX

final class CalendarMonthModelTests: XCTestCase {
    private func cal(firstWeekday: Int = 1) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = firstWeekday
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ c: Calendar) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testOctober2026StartsThursday() {
        let c = cal()
        let cells = CalendarMonthModel(containing: date(2026, 10, 9, c), calendar: c).cells
        XCTAssertEqual(cells.count, 35)
        XCTAssertEqual(cells.prefix(4).compactMap { $0 }.count, 0, "4 leading blanks")
        XCTAssertEqual(cells[4]?.number, 1)
        XCTAssertEqual(cells.compactMap { $0 }.count, 31)
    }

    func testFebruary2026StartsSundayHasExactlyFourRows() {
        let c = cal()
        let cells = CalendarMonthModel(containing: date(2026, 2, 14, c), calendar: c).cells
        XCTAssertEqual(cells.count, 28)
        XCTAssertEqual(cells.first??.number, 1)
    }

    func testAugust2026NeedsSixRows() {
        let c = cal()
        let cells = CalendarMonthModel(containing: date(2026, 8, 1, c), calendar: c).cells
        XCTAssertEqual(cells.count, 42)
        XCTAssertEqual(cells[6]?.number, 1)
    }

    func testMondayFirstShiftsLeadingBlanks() {
        let c = cal(firstWeekday: 2)
        let cells = CalendarMonthModel(containing: date(2026, 10, 9, c), calendar: c).cells
        XCTAssertEqual(cells[3]?.number, 1)
        XCTAssertNil(cells[2])
    }

    func testAddingMonthsRollsOverYear() {
        let c = cal()
        let dec = CalendarMonthModel(containing: date(2026, 12, 20, c), calendar: c)
        let jan = dec.adding(months: 1)
        XCTAssertEqual(c.component(.year, from: jan.monthStart), 2027)
        XCTAssertEqual(c.component(.month, from: jan.monthStart), 1)
        let back = jan.adding(months: -1)
        XCTAssertEqual(c.component(.month, from: back.monthStart), 12)
    }

    func testWeekdaySymbolsRotateWithFirstWeekday() {
        XCTAssertEqual(CalendarMonthModel(containing: Date(), calendar: cal()).weekdaySymbols.count, 7)
        let mon = CalendarMonthModel(containing: Date(), calendar: cal(firstWeekday: 2)).weekdaySymbols
        XCTAssertEqual(mon.first, cal().veryShortStandaloneWeekdaySymbols[1])
    }

    func testPhaseLookupNilOnDayWithoutEvent() {
        let c = cal()
        let events = [Event(eventType: .ovulation, date: date(2026, 10, 9, c), note: "")]
        XCTAssertEqual(CalendarPhaseLookup.phase(on: date(2026, 10, 9, c), events: events, calendar: c), .ovulation)
        XCTAssertNil(CalendarPhaseLookup.phase(on: date(2026, 10, 10, c), events: events, calendar: c))
    }

    func testPredictedPeriodWindow() {
        let c = cal()
        let start = date(2026, 10, 24, c)
        XCTAssertTrue(CalendarPhaseLookup.isPredictedPeriod(date(2026, 10, 24, c), start: start, length: 5, calendar: c))
        XCTAssertTrue(CalendarPhaseLookup.isPredictedPeriod(date(2026, 10, 28, c), start: start, length: 5, calendar: c))
        XCTAssertFalse(CalendarPhaseLookup.isPredictedPeriod(date(2026, 10, 29, c), start: start, length: 5, calendar: c))
        XCTAssertFalse(CalendarPhaseLookup.isPredictedPeriod(date(2026, 10, 23, c), start: start, length: 5, calendar: c))
        XCTAssertFalse(CalendarPhaseLookup.isPredictedPeriod(date(2026, 10, 24, c), start: nil, length: 5, calendar: c))
    }
}
