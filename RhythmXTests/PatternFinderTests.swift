import XCTest
@testable import RhythmX

/// Task 10B: the deterministic PatternFinder behind the Patterns segment of the Tags tab.
final class PatternFinderTests: XCTestCase {
    private let calendar = Calendar.current
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14))!

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    private func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today)! }

    /// Phase for a day of a 28-day cycle: 1-5 menstrual, 6-13 follicular, 14-16 ovulation, 17-28 luteal.
    private func phase(forDay day: Int) -> Event.EventType {
        switch day {
        case ...5: return .menstrual
        case 6...13: return .follicular
        case 14...16: return .ovulation
        default: return .luteal
        }
    }

    /// One 28-day cycle starting on `start`, with `tags` on the given cycle days.
    private func cycleEvents(start: Date, tags: [Int: String], mode: TrackingMode? = nil) -> [Event] {
        (1...28).map { day in
            Event(eventType: phase(forDay: day),
                  date: calendar.date(byAdding: .day, value: day - 1, to: start)!,
                  note: "",
                  tags: tags[day] ?? "",
                  mode: mode)
        }
    }

    private func block(start: Date, tags: [Int: String], mode: TrackingMode? = nil) -> ArchivedDataBlock {
        let events = cycleEvents(start: start, tags: tags, mode: mode)
        let grouped = Dictionary(grouping: events) { $0.eventType }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) }
        return ArchivedDataBlock(date: calendar.date(byAdding: .day, value: 28, to: start)!, groupedEvents: grouped, mode: mode)
    }

    /// `count` archived cycles, oldest first, each with Cramps on days 1 to 3.
    private func crampCycles(_ count: Int) -> [ArchivedDataBlock] {
        (0..<count).map { i in
            block(start: date(2026, 1 + i, 1), tags: [1: "Symptom:Cramps", 2: "Symptom:Cramps", 3: "Symptom:Cramps"])
        }
    }

    private func carrier(_ date: Date, _ tags: String) -> Event {
        Event(eventType: .follicular, date: date, note: "", tags: tags, mode: .menopause)
    }

    // MARK: - Findings

    func testFindingsRequireEvidenceInAtLeastThreeCycles() {
        XCTAssertEqual(PatternFinder.findings(events: [], archivedBlocks: crampCycles(2), mode: .cycle), [],
                       "two cycles with the pattern are not enough evidence")

        let findings = PatternFinder.findings(events: [], archivedBlocks: crampCycles(3), mode: .cycle)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.tag, "Symptom:Cramps")
        XCTAssertEqual(findings.first?.sentence, "Cramps came up on days 1 to 3, in your menstrual phase")
        XCTAssertEqual(findings.first?.evidence, "3 of your last 3 cycles")
    }

    func testFindingsUseTheLastSixCyclesAndSkipWeakPatterns() {
        // Eight cycles: Cramps on days 1-3 in the last five; Headache on day 25 in the oldest three only.
        var blocks: [ArchivedDataBlock] = []
        for i in 0..<8 {
            var tags: [Int: String] = [:]
            if i >= 3 { tags[1] = "Symptom:Cramps"; tags[2] = "Symptom:Cramps"; tags[3] = "Symptom:Cramps" }
            if i < 3 { tags[25] = "Symptom:Headache" }
            blocks.append(block(start: date(2026, 1 + i, 1), tags: tags))
        }
        let findings = PatternFinder.findings(events: [], archivedBlocks: blocks, mode: .cycle)

        XCTAssertEqual(findings.map(\.tag), ["Symptom:Cramps"],
                       "the headache cycles fall outside the last six, so only one cycle of evidence remains")
        XCTAssertEqual(findings.first?.evidence, "5 of your last 6 cycles")
    }

    func testAtMostThreeFindingsStrongestFirst() {
        let blocks = (0..<6).map { i -> ArchivedDataBlock in
            var tags: [Int: String] = [1: "Symptom:Cramps", 25: "Symptom:Headache", 10: "Mood:Happy"]
            if i < 4 { tags[15] = "Mood:Focused" }
            if i >= 2 { tags[20] = "Symptom:Bloating" }   // in 4 cycles too, but sorts after Focused by name
            return block(start: date(2026, 1 + i, 1), tags: tags)
        }
        let findings = PatternFinder.findings(events: [], archivedBlocks: blocks, mode: .cycle)

        XCTAssertEqual(findings.count, 3)
        XCTAssertEqual(Set(findings.prefix(3).map(\.tag)), ["Symptom:Cramps", "Symptom:Headache", "Mood:Happy"],
                       "the three tags seen in all six cycles win over the ones seen in four")
        XCTAssertEqual(findings.first?.sentence, "Cramps came up on day 1, in your menstrual phase")
    }

    func testLiveCycleCountsAsACycleOnlyWhenItHasTags() {
        let blocks = crampCycles(2)
        let liveStart = date(2026, 3, 1)
        let untagged = cycleEvents(start: liveStart, tags: [:])
        XCTAssertEqual(PatternFinder.cyclesAvailable(events: untagged, archivedBlocks: blocks), 2)
        XCTAssertEqual(PatternFinder.findings(events: untagged, archivedBlocks: blocks, mode: .cycle), [])

        let tagged = cycleEvents(start: liveStart, tags: [2: "Symptom:Cramps"])
        XCTAssertEqual(PatternFinder.cyclesAvailable(events: tagged, archivedBlocks: blocks), 3)
        let findings = PatternFinder.findings(events: tagged, archivedBlocks: blocks, mode: .cycle)
        XCTAssertEqual(findings.first?.evidence, "3 of your last 3 cycles")
    }

    func testSparseDataReturnsEmptyFindings() {
        XCTAssertEqual(PatternFinder.findings(events: [], archivedBlocks: [], mode: .cycle), [])
        XCTAssertEqual(PatternFinder.findings(events: [], archivedBlocks: crampCycles(1), mode: .cycle), [])
        XCTAssertEqual(PatternFinder.findings(events: [], archivedBlocks: [], mode: .menopause, today: today), [])
        XCTAssertEqual(PatternFinder.heatmap(events: [], archivedBlocks: [], mode: .cycle), [])
        XCTAssertEqual(PatternFinder.cycleDayCounts(tag: "Symptom:Cramps", events: [], archivedBlocks: []), [])
    }

    func testEmptyStateSaysHowManyMoreCyclesAreNeeded() {
        XCTAssertEqual(PatternFinder.minimumCycles, 3)
        XCTAssertEqual(PatternFinder.cyclesNeeded(available: 0), 3)
        XCTAssertEqual(PatternFinder.cyclesNeeded(available: 1), 2)
        XCTAssertEqual(PatternFinder.cyclesNeeded(available: 2), 1)
        XCTAssertEqual(PatternFinder.cyclesNeeded(available: 3), 0)
        XCTAssertEqual(PatternFinder.cyclesNeeded(available: 9), 0)

        let one = TagPatternsViewModel(events: [], archivedBlocks: crampCycles(1), mode: .cycle,
                                       summarizer: PatternSummaryProvider(), today: today)
        XCTAssertEqual(one.cyclesNeeded, 2)
        XCTAssertEqual(one.emptyStateMessage, "Log 2 more cycles to see patterns here.")

        let two = TagPatternsViewModel(events: [], archivedBlocks: crampCycles(2), mode: .planning,
                                       summarizer: PatternSummaryProvider(), today: today)
        XCTAssertEqual(two.emptyStateMessage, "Log 1 more cycle to see patterns here.")
    }

    // MARK: - Heatmap

    func testMenopauseEventsNeverAppearInCycleHeatmaps() {
        let live = cycleEvents(start: date(2026, 9, 20), tags: [1: "Symptom:Cramps", 2: "Symptom:Cramps"])
            + [carrier(daysAgo(1), "Menopause:Hot Flashes, Menopause:Hot Flashes"),
               carrier(daysAgo(3), "Menopause:Night Sweats")]
        let blocks = crampCycles(2) + [block(start: date(2026, 5, 1), tags: [4: "Menopause:Brain Fog"], mode: .menopause)]

        let cycleRows = PatternFinder.heatmap(events: live, archivedBlocks: blocks, mode: .cycle, today: today)
        XCTAssertEqual(cycleRows.map(\.tag), ["Symptom:Cramps"])
        XCTAssertFalse(cycleRows.contains { $0.tag.hasPrefix("Menopause:") })
        XCTAssertEqual(PatternFinder.heatmap(events: live, archivedBlocks: blocks, mode: .planning, today: today).map(\.tag),
                       ["Symptom:Cramps"])

        let menopauseRows = PatternFinder.heatmap(events: live, archivedBlocks: blocks, mode: .menopause, today: today)
        XCTAssertEqual(Set(menopauseRows.map(\.tag)), ["Menopause:Hot Flashes", "Menopause:Night Sweats"],
                       "menopause rows come from menopause events; cycle tags and events older than 8 weeks stay out")

        // Findings and the drill-down are filtered the same way.
        XCTAssertFalse(PatternFinder.findings(events: live, archivedBlocks: blocks, mode: .cycle).contains { $0.tag.hasPrefix("Menopause:") })
        XCTAssertEqual(PatternFinder.cycleDayCounts(tag: "Menopause:Hot Flashes", events: live, archivedBlocks: blocks), [])
    }

    func testHeatmapUsesEightWeeksInMenopauseAndFourPhasesOtherwise() {
        let live = cycleEvents(start: date(2026, 9, 20), tags: [1: "Symptom:Cramps", 20: "Symptom:Cramps"])
            + [carrier(daysAgo(2), "Menopause:Hot Flashes")]

        for mode in [TrackingMode.cycle, .planning] {
            let rows = PatternFinder.heatmap(events: live, archivedBlocks: [], mode: mode, today: today)
            let row = rows.first
            XCTAssertEqual(row?.cells.count, 4, "\(mode)")
            XCTAssertEqual(row?.cells.map(\.phase), Event.EventType.allCases, "\(mode)")
            XCTAssertEqual(row?.cells.map(\.weekIndex), [nil, nil, nil, nil], "\(mode)")
            XCTAssertEqual(row?.cells.map(\.count), [1, 0, 0, 1], "\(mode)")
        }

        let rows = PatternFinder.heatmap(events: live, archivedBlocks: [], mode: .menopause, today: today)
        let row = rows.first
        XCTAssertEqual(row?.cells.count, 8)
        XCTAssertEqual(row?.cells.map(\.weekIndex), Array(0..<8), "oldest week first")
        XCTAssertEqual(row?.cells.map(\.phase), Array(repeating: nil, count: 8))
        XCTAssertEqual(row?.cells.map(\.count), [0, 0, 0, 0, 0, 0, 0, 1])
    }

    func testRepeatedTagsCountEachOccurrence() {
        let live = [
            carrier(daysAgo(1), "Menopause:Hot Flashes, Menopause:Hot Flashes, Menopause:Hot Flashes"),
            carrier(daysAgo(10), "Menopause:Hot Flashes")
        ]
        let rows = PatternFinder.heatmap(events: live, archivedBlocks: [], mode: .menopause, today: today)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, "Menopause:Hot Flashes")
        XCTAssertEqual(rows.first?.cells.last?.count, 3, "three same-day tags count 3 in this week's cell")
        XCTAssertEqual(rows.first?.cells[6].count, 1)

        // Same rule in a cycle: two Cramps on one day count twice in the phase cell.
        let cycle = cycleEvents(start: date(2026, 9, 20), tags: [2: "Symptom:Cramps, Symptom:Cramps"])
        let cycleRows = PatternFinder.heatmap(events: cycle, archivedBlocks: [], mode: .cycle, today: today)
        XCTAssertEqual(cycleRows.first?.cells.first?.count, 2)
    }

    func testHeatmapRowsAreMostFrequentFirstAndCapped() {
        var tags: [Int: String] = [:]
        for day in 1...12 { tags[day] = "Mood:Tag\(day)" }        // twelve different tags once each
        tags[20] = "Symptom:Cramps, Symptom:Cramps, Symptom:Cramps"
        let rows = PatternFinder.heatmap(events: cycleEvents(start: date(2026, 9, 1), tags: tags), archivedBlocks: [], mode: .cycle)

        XCTAssertEqual(rows.first?.tag, "Symptom:Cramps")
        XCTAssertEqual(rows.count, PatternFinder.maxRows)
        XCTAssertLessThan(PatternFinder.maxRows, 13)
    }

    // MARK: - Tag detail

    func testCycleDayCountsSumAcrossCyclesWithThePhaseOfThatDay() {
        let blocks = crampCycles(3) + [block(start: date(2026, 6, 1), tags: [3: "Symptom:Cramps, Symptom:Cramps", 25: "Symptom:Cramps"])]
        let counts = PatternFinder.cycleDayCounts(tag: "Symptom:Cramps", events: [], archivedBlocks: blocks)

        XCTAssertEqual(counts.map(\.cycleDay), [1, 2, 3, 25])
        XCTAssertEqual(counts.map(\.count), [3, 3, 5, 1])
        XCTAssertEqual(counts.map(\.phase), [.menstrual, .menstrual, .menstrual, .luteal])
        XCTAssertEqual(counts.map(\.id), counts.map(\.cycleDay))
    }

    func testPhaseBandsFollowTheCycles() {
        let bands = PatternFinder.phaseBands(events: [], archivedBlocks: crampCycles(2))
        XCTAssertEqual(bands.map(\.phase), Event.EventType.allCases)
        XCTAssertEqual(bands.map(\.startDay), [1, 6, 14, 17])
        XCTAssertEqual(bands.map(\.endDay), [5, 13, 16, 28])
        XCTAssertEqual(PatternFinder.phaseBands(events: [], archivedBlocks: []), [])
    }

    func testFindingForOneTagMatchesTheList() {
        let blocks = crampCycles(4)
        let listed = PatternFinder.findings(events: [], archivedBlocks: blocks, mode: .cycle).first
        XCTAssertEqual(PatternFinder.finding(for: "Symptom:Cramps", events: [], archivedBlocks: blocks, mode: .cycle), listed)
        XCTAssertNil(PatternFinder.finding(for: "Symptom:Headache", events: [], archivedBlocks: blocks, mode: .cycle))
    }

    // MARK: - Menopause findings

    func testMenopauseFindingsCountWeeks() {
        let live = [
            carrier(daysAgo(1), "Menopause:Hot Flashes, Menopause:Hot Flashes"),
            carrier(daysAgo(9), "Menopause:Hot Flashes"),
            carrier(daysAgo(16), "Menopause:Hot Flashes"),
            carrier(daysAgo(2), "Menopause:Night Sweats")
        ]
        let findings = PatternFinder.findings(events: live, archivedBlocks: [], mode: .menopause, today: today)

        XCTAssertEqual(findings.map(\.tag), ["Menopause:Hot Flashes"], "Night Sweats has one week of evidence only")
        XCTAssertEqual(findings.first?.sentence, "Hot Flashes came up 4 times")
        XCTAssertEqual(findings.first?.evidence, "3 of the last 8 weeks")
    }
}
