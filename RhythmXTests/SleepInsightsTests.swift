import XCTest
@testable import RhythmX

/// The Sleep card in Menopause Insights: last 7 nights from the imported Health summary, the average and the
/// hours text. Pure numbers, no HealthKit.
final class SleepInsightsTests: XCTestCase {
    private let calendar = Calendar.current
    private let today = Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 15))!
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))!
    }

    func testLastSevenNightsOldestFirstEndingToday() {
        let summary: [Date: TimeInterval] = [
            day(0): 7 * 3600,
            day(-1): 6.5 * 3600,
            day(-6): 8 * 3600,
            day(-7): 9 * 3600,     // eight nights ago: outside the card
            day(1): 5 * 3600,      // a future day cannot happen, but is ignored
        ]

        let sleep = SleepInsights.make(summary: summary, today: today, calendar: calendar)

        XCTAssertEqual(sleep.nights.map(\.date), (-6...0).map { day($0) })
        XCTAssertEqual(sleep.nights.map(\.hours), [8, nil, nil, nil, nil, 6.5, 7])
        XCTAssertTrue(sleep.hasData)
    }

    func testAverageCountsOnlyNightsWithSleep() {
        let summary: [Date: TimeInterval] = [day(0): 7 * 3600, day(-1): 6 * 3600, day(-3): 8.5 * 3600]

        let sleep = SleepInsights.make(summary: summary, today: today, calendar: calendar)

        XCTAssertEqual(sleep.averageHours ?? 0, 7.1666, accuracy: 0.001)
        XCTAssertEqual(sleep.nightsWithSleep, 3)
    }

    func testNoDataInTheLastSevenNights() {
        let sleep = SleepInsights.make(summary: [day(-10): 7 * 3600, day(-2): 0], today: today, calendar: calendar)

        XCTAssertFalse(sleep.hasData, "a zero-length night is no data")
        XCTAssertNil(sleep.averageHours)
        XCTAssertEqual(sleep.nights.count, 7)
    }

    func testHoursRoundToOneDecimal() {
        XCTAssertEqual(SleepInsights.hoursText(7), "7 h")
        XCTAssertEqual(SleepInsights.hoursText(7.25), "7.3 h")
        XCTAssertEqual(SleepInsights.hoursText(6.94), "6.9 h")
        XCTAssertEqual(SleepInsights.hoursText(6.96), "7 h")
        XCTAssertEqual(SleepInsights.spokenHours(7.25), "7.3 hours")
        XCTAssertEqual(SleepInsights.spokenHours(1), "1 hour")
    }

    func testAccessibilitySummary() {
        let summary: [Date: TimeInterval] = [day(0): 7 * 3600, day(-1): 6 * 3600]
        let sleep = SleepInsights.make(summary: summary, today: today, calendar: calendar)

        XCTAssertEqual(sleep.accessibilitySummary, "Average 6.5 hours asleep over 2 of the last 7 nights. Last night 7 hours.")
        XCTAssertEqual(SleepInsights.make(summary: [:], today: today, calendar: calendar).accessibilitySummary,
                       "No sleep from Apple Health in the last 7 nights.")
    }

    func testEmptyMessageExplainsSourceAndSettings() {
        let off = SleepInsights.emptyMessage(readSleepOn: false)
        XCTAssertTrue(off.contains("Apple Health"))
        XCTAssertTrue(off.contains("Sleep Focus"))
        XCTAssertTrue(off.contains("Apple Watch"))
        XCTAssertTrue(off.contains("Settings"))
        XCTAssertTrue(off.contains("Read sleep"))

        let noData = SleepInsights.emptyMessage(readSleepOn: true)
        XCTAssertTrue(noData.contains("Sleep Focus"))
        XCTAssertFalse(noData.contains("turn on"), "already on, so it does not ask to turn it on")
        for text in [off, noData] { XCTAssertFalse(text.contains("\u{2014}"), "no em dashes in UI copy") }
    }
}
