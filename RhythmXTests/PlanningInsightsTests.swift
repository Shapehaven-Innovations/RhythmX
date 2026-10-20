import XCTest
@testable import RhythmX

/// Task 8: the pure Planning insights behind the Planning mode of the Insights tab.
@MainActor
final class PlanningInsightsTests: XCTestCase {
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: anchor)! }

    /// A generated 28-day cycle: ovulation phase on offsets 13...15, so the auto fertile window is 8...15.
    private var cycle: [Event] { CycleGenerator.events(startDate: anchor, cycleLength: 28) }

    private func tagged(_ events: [Event], offset: Int, tags: String) -> [Event] {
        events.map { e in
            guard Calendar.current.isDate(e.date, inSameDayAs: day(offset)) else { return e }
            var copy = e
            copy.tags = copy.tags.isEmpty ? tags : copy.tags + ", " + tags
            return copy
        }
    }

    // MARK: - Fertile window

    func testFertileWindowFromEvents() {
        let insights = PlanningInsights.make(events: cycle, overrides: FertileOverrides(), today: day(10))

        XCTAssertEqual(insights.fertileWindow, day(8)...day(15))
        XCTAssertEqual(insights.likelyOvulation, day(13), "the first ovulation-phase day")
        XCTAssertEqual(insights.daysToOvulation, 3)
        XCTAssertEqual(insights.fertilityLevel, .high)
        XCTAssertNil(insights.twoWeekWaitDay, "ovulation has not happened yet")
    }

    func testFertileWindowHonorsOverrides() {
        let overrides = FertileOverrides(added: [FertileWindow.dayKey(day(7))], removed: [FertileWindow.dayKey(day(15))])
        let insights = PlanningInsights.make(events: cycle, overrides: overrides, today: day(10))

        XCTAssertEqual(insights.fertileWindow, day(7)...day(14))
    }

    func testMenopauseEventsNeverWidenTheWindow() {
        let stray = Event(id: "M", eventType: .ovulation, date: day(40), note: "", tags: "Menopause:Hot Flashes", mode: .menopause)
        let insights = PlanningInsights.make(events: cycle + [stray], overrides: FertileOverrides(), today: day(10))

        XCTAssertEqual(insights.fertileWindow, day(8)...day(15))
        XCTAssertEqual(insights.likelyOvulation, day(13))
    }

    func testDaysToOvulationNilWhenNoCycle() {
        let insights = PlanningInsights.make(events: [], overrides: FertileOverrides(), today: day(10))

        XCTAssertNil(insights.fertileWindow)
        XCTAssertNil(insights.likelyOvulation)
        XCTAssertNil(insights.daysToOvulation)
        XCTAssertNil(insights.twoWeekWaitDay)
        XCTAssertEqual(insights.fertilityLevel, .low)
        XCTAssertTrue(insights.temperatures.isEmpty)
        XCTAssertTrue(insights.testResults.isEmpty)
        XCTAssertFalse(insights.hasCycle)
    }

    func testFertilityLevelFollowsTheWindow() {
        func level(on offset: Int) -> PlanningInsights.Level {
            PlanningInsights.make(events: cycle, overrides: FertileOverrides(), today: day(offset)).fertilityLevel
        }
        XCTAssertEqual(level(on: 2), .low)
        XCTAssertEqual(level(on: 5), .rising, "three days before the window opens")
        XCTAssertEqual(level(on: 10), .high)
        XCTAssertEqual(level(on: 13), .peak, "likely ovulation day")
        XCTAssertEqual(level(on: 20), .low)
    }

    // MARK: - Temperatures

    func testTemperaturePointsParsedFromTags() {
        var events = cycle
        events = tagged(events, offset: 6, tags: "Basal Temp:97.8")
        events = tagged(events, offset: 3, tags: "Mood:Calm, Basal Temp: 97.4")
        events = tagged(events, offset: 9, tags: "Basal Temp:Elevated BBT")
        events = tagged(events, offset: 12, tags: "Basal Temp:36.6 C")

        let points = PlanningInsights.make(events: events, overrides: FertileOverrides(), today: day(10)).temperatures

        XCTAssertEqual(points, [
            PlanningInsights.TempPoint(date: day(3), value: 97.4),
            PlanningInsights.TempPoint(date: day(6), value: 97.8),
            PlanningInsights.TempPoint(date: day(12), value: 36.6)
        ], "sorted by date; a word value such as Elevated BBT is not a point")
    }

    func testTemperaturesIgnoreMenopauseEvents() {
        let stray = Event(id: "M", eventType: .luteal, date: day(4), note: "", tags: "Basal Temp:98.0", mode: .menopause)
        let points = PlanningInsights.make(events: cycle + [stray], overrides: FertileOverrides(), today: day(10)).temperatures
        XCTAssertTrue(points.isEmpty)
    }

    // MARK: - Two-week wait and test results

    func testTwoWeekWaitDayCountsFromConfirmedOvulation() {
        // No test result: the count runs from the likely ovulation day (offset 13).
        let unconfirmed = PlanningInsights.make(events: cycle, overrides: FertileOverrides(), today: day(20))
        XCTAssertEqual(unconfirmed.twoWeekWaitDay, 7)
        XCTAssertNil(unconfirmed.daysToOvulation, "no countdown once ovulation has passed")

        // A peak test on offset 15 confirms ovulation there, so the wait counts from that day.
        let events = tagged(cycle, offset: 15, tags: "Planning:Ovulation Test Peak")
        let confirmed = PlanningInsights.make(events: events, overrides: FertileOverrides(), today: day(20))
        XCTAssertEqual(confirmed.twoWeekWaitDay, 5)
        XCTAssertEqual(confirmed.testResults, [PlanningInsights.TestPoint(date: day(15), result: .peak)])

        // The wait is two weeks long.
        XCTAssertEqual(PlanningInsights.make(events: events, overrides: FertileOverrides(), today: day(29)).twoWeekWaitDay, 14)
        XCTAssertNil(PlanningInsights.make(events: events, overrides: FertileOverrides(), today: day(30)).twoWeekWaitDay)
    }

    func testTestResultsReadFromPlanningTags() {
        var events = tagged(cycle, offset: 11, tags: "Planning:Ovulation Test Negative")
        events = tagged(events, offset: 12, tags: "Planning:Ovulation Test Faint, Planning:Intercourse")
        events = tagged(events, offset: 13, tags: "Planning:Ovulation Test Positive")

        let insights = PlanningInsights.make(events: events, overrides: FertileOverrides(), today: day(13))

        XCTAssertEqual(insights.testResults.map(\.result), [.negative, .faint, .positive])
        XCTAssertEqual(insights.latestTest?.result, .positive)
        XCTAssertEqual(insights.fertilityLevel, .peak)
    }

    // MARK: - Legend

    func testLegendShowsPlanningOnlyWhenPlanningTagsExist() {
        let plain = InsightsViewModel(events: cycle, archivedBlocks: [], appSettings: AppSettings())
        XCTAssertFalse(plain.categoryLegendItems.map(\.name).contains("Planning"),
                       "Cycle-mode Insights look as before when no planning tags were logged")

        let withPlanning = InsightsViewModel(events: tagged(cycle, offset: 12, tags: "Planning:Intercourse"),
                                             archivedBlocks: [], appSettings: AppSettings())
        XCTAssertTrue(withPlanning.categoryLegendItems.map(\.name).contains("Planning"))
        XCTAssertTrue(InsightsViewModel.categoryNames.contains("Planning"), "the chart color scale knows the category")
    }
}
