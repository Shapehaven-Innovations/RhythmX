import XCTest
@testable import RhythmX

/// Task 8: the pure Menopause insights behind the Menopause mode of the Insights tab.
@MainActor
final class MenopauseInsightsTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14))!
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: today)! }

    private func carrier(_ date: Date, _ tags: String, id: String = UUID().uuidString) -> Event {
        Event(id: id, eventType: .follicular, date: date, note: "", tags: tags, mode: .menopause)
    }

    // MARK: - Months since last period

    func testMonthsSinceLastPeriodIsZeroWhenLoggedThisMonth() {
        let events = [Event(eventType: .menstrual, date: date(2026, 10, 2), note: "")]
        let insights = MenopauseInsights.make(events: events, today: today)

        XCTAssertEqual(insights.lastPeriod, date(2026, 10, 2))
        XCTAssertEqual(insights.monthsSinceLastPeriod, 0)
    }

    func testMonthsSinceLastPeriodCountsWholeMonths() {
        let march14 = MenopauseInsights.make(events: [Event(eventType: .menstrual, date: date(2026, 3, 14), note: "")], today: today)
        XCTAssertEqual(march14.monthsSinceLastPeriod, 7)

        let march15 = MenopauseInsights.make(events: [Event(eventType: .menstrual, date: date(2026, 3, 15), note: "")], today: today)
        XCTAssertEqual(march15.monthsSinceLastPeriod, 6, "only whole months count")
    }

    func testLastPeriodIsTheLatestCyclePeriodOnOrBeforeToday() {
        let events = [
            Event(eventType: .menstrual, date: date(2026, 1, 3), note: ""),
            Event(eventType: .menstrual, date: date(2026, 3, 14), note: ""),
            Event(eventType: .follicular, date: date(2026, 9, 1), note: ""),
            Event(eventType: .menstrual, date: date(2026, 9, 20), note: "", mode: .menopause),
            Event(eventType: .menstrual, date: date(2026, 11, 1), note: "")
        ]
        let insights = MenopauseInsights.make(events: events, today: today)

        XCTAssertEqual(insights.lastPeriod, date(2026, 3, 14),
                       "a menopause carrier is not a period and a future generated day has not happened")
        XCTAssertEqual(insights.monthsSinceLastPeriod, 7)
    }

    // MARK: - Hot flashes per week

    func testHotFlashesPerWeekCountsRepeatedTags() {
        let events = [
            carrier(daysAgo(1), "Menopause:Hot Flashes, Menopause:Hot Flashes, Menopause:Hot Flashes"),
            carrier(daysAgo(13), "Other:Hot Flashes, Menopause:Night Sweats"),
            carrier(daysAgo(55), "Menopause:Hot Flashes"),
            carrier(daysAgo(56), "Menopause:Hot Flashes, Menopause:Hot Flashes")
        ]
        let insights = MenopauseInsights.make(events: events, today: today)

        XCTAssertEqual(insights.hotFlashesPerWeek.count, 8)
        XCTAssertEqual(insights.hotFlashesPerWeek, [1, 0, 0, 0, 0, 0, 1, 3],
                       "oldest week first; three same-day tags count 3; 56 days ago is outside the 8 weeks")
    }

    // MARK: - This week

    func testWeekSummaryCountsTheCurrentWeekOnly() {
        let events = [
            carrier(today, "Menopause:Night Sweats, Mood:Calm, Menopause:Hot Flashes, Menopause:Hot Flashes"),
            carrier(daysAgo(6), "Other:Poor Sleep, Symptom:Cramps, Exercise:Yoga"),
            carrier(daysAgo(7), "Menopause:Brain Fog")
        ]
        let insights = MenopauseInsights.make(events: events, today: today)

        XCTAssertEqual(insights.weekSummary, ["Night Sweats": 1, "Calm": 1, "Hot Flashes": 2, "Poor Sleep": 1],
                       "menopause and mood tags from the last 7 days, each occurrence counted; other symptoms stay out")
        XCTAssertEqual(insights.weekRows.map(\.label), ["Hot Flashes", "Calm", "Night Sweats", "Poor Sleep"],
                       "most frequent first, then alphabetical")
    }

    func testNoDataYieldsEmptyStateNotCrash() {
        let insights = MenopauseInsights.make(events: [], today: today)

        XCTAssertNil(insights.lastPeriod)
        XCTAssertEqual(insights.monthsSinceLastPeriod, 0)
        XCTAssertEqual(insights.hotFlashesPerWeek, Array(repeating: 0, count: 8))
        XCTAssertTrue(insights.weekSummary.isEmpty)
        XCTAssertFalse(insights.hasData)

        let withPeriod = MenopauseInsights.make(events: [Event(eventType: .menstrual, date: date(2026, 3, 14), note: "")], today: today)
        XCTAssertTrue(withPeriod.hasData)
    }

    // MARK: - Legend

    func testLegendShowsMenopauseOnlyWhenMenopauseTagsExist() {
        let plain = InsightsViewModel(events: [Event(eventType: .luteal, date: today, note: "", tags: "Mood:Calm")],
                                      archivedBlocks: [], appSettings: AppSettings())
        XCTAssertFalse(plain.categoryLegendItems.map(\.name).contains("Menopause"))

        let withMenopause = InsightsViewModel(events: [Event(eventType: .luteal, date: today, note: "", tags: "Menopause:Brain Fog")],
                                              archivedBlocks: [], appSettings: AppSettings())
        XCTAssertTrue(withMenopause.categoryLegendItems.map(\.name).contains("Menopause"))
        XCTAssertTrue(InsightsViewModel.categoryNames.contains("Menopause"))
    }
}
