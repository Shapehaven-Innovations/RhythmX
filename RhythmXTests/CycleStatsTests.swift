import XCTest
@testable import RhythmX

@MainActor
final class CycleStatsTests: XCTestCase {
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: anchor)!
    }

    private func vm(events: [Event] = [], blocks: [ArchivedDataBlock] = []) -> InsightsViewModel {
        InsightsViewModel(events: events, archivedBlocks: blocks, appSettings: AppSettings())
    }

    private func block(length: Int, start: Date) -> ArchivedDataBlock {
        let events = CycleGenerator.events(startDate: start, cycleLength: length)
        let grouped = Dictionary(grouping: events, by: { $0.eventType })
            .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) }
        return ArchivedDataBlock(date: start, groupedEvents: grouped)
    }

    func testNoDataGivesAllNil() {
        let s = vm().cycleStats(today: anchor)
        XCTAssertNil(s.averageCycleLength)
        XCTAssertNil(s.averagePeriodLength)
        XCTAssertNil(s.currentCycleDay)
        XCTAssertNil(s.currentPhase)
        XCTAssertNil(s.nextPeriodEstimate)
    }

    func testCurrentCycleMidOvulation() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        let s = vm(events: events).cycleStats(today: day(13))
        XCTAssertEqual(s.currentCycleDay, 14)
        XCTAssertEqual(s.currentPhase, .ovulation)
        XCTAssertEqual(s.averageCycleLength, 28)
        XCTAssertEqual(s.averagePeriodLength, 5)
        XCTAssertEqual(s.nextPeriodEstimate, day(28))
    }

    func testTodayBeforeCycleStartHasNoDay() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        let s = vm(events: events).cycleStats(today: day(-3))
        XCTAssertNil(s.currentCycleDay)
        XCTAssertNil(s.currentPhase)
    }

    func testTodayAfterCycleEndHasNoDayButKeepsEstimate() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 28)
        let s = vm(events: events).cycleStats(today: day(40))
        XCTAssertNil(s.currentCycleDay)
        XCTAssertNil(s.currentPhase)
        XCTAssertEqual(s.nextPeriodEstimate, day(28))
    }

    func testAveragesFromArchivesWhenNoCurrentCycle() {
        let blocks = [block(length: 28, start: day(-60)), block(length: 30, start: day(-30))]
        let s = vm(blocks: blocks).cycleStats(today: anchor)
        XCTAssertEqual(s.averageCycleLength, 29)
        XCTAssertEqual(s.averagePeriodLength, 5)
        XCTAssertNil(s.currentCycleDay)
        XCTAssertNotNil(s.nextPeriodEstimate)
    }

    func testShortestCycleLength20() {
        let events = CycleGenerator.events(startDate: anchor, cycleLength: 20)
        let s = vm(events: events).cycleStats(today: day(19))
        XCTAssertEqual(s.currentCycleDay, 20)
        XCTAssertEqual(s.currentPhase, .luteal)
        XCTAssertEqual(s.nextPeriodEstimate, day(20))
    }
}
