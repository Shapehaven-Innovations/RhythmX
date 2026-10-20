import PDFKit
import XCTest
@testable import RhythmX

/// Task 14: the Doctor Report numbers and its one-page PDF. Cycle data only, a Menopause variant on request,
/// and nothing typed into the name or birth date fields is ever stored.
@MainActor
final class DoctorReportTests: XCTestCase {
    private let calendar = Calendar.current
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14))!

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func block(start: Date, length: Int, mode: TrackingMode? = nil, tags: String = "") -> ArchivedDataBlock {
        var events = CycleGenerator.events(startDate: start, cycleLength: length)
        if !tags.isEmpty { events[0].tags = tags }
        let grouped = Dictionary(grouping: events, by: { $0.eventType })
            .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) }
        return ArchivedDataBlock(date: start, groupedEvents: grouped, mode: mode)
    }

    private func block(events: [Event], mode: TrackingMode? = nil) -> ArchivedDataBlock {
        let grouped = Dictionary(grouping: events, by: { $0.eventType })
            .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) }
        return ArchivedDataBlock(date: events.map(\.date).min() ?? today, groupedEvents: grouped, mode: mode)
    }

    private func menstrual(_ day: Date) -> Event {
        Event(eventType: .menstrual, date: day, note: "")
    }

    private func report(events: [Event] = [], blocks: [ArchivedDataBlock] = [], mode: TrackingMode = .cycle) -> DoctorReport {
        DoctorReportBuilder.make(events: events, archivedBlocks: blocks, mode: mode, today: today)
    }

    private func pageText(_ data: Data) throws -> String {
        let doc = try XCTUnwrap(PDFDocument(data: data), "renderer output is a PDF")
        XCTAssertEqual(doc.pageCount, 1, "the report is one page")
        return try XCTUnwrap(doc.page(at: 0)?.string)
    }

    // MARK: - Numbers

    func testNeedsTwoCompletedCyclesElseHasEnoughDataFalse() {
        // A cycle is complete once the next period has started.
        let current = CycleGenerator.events(startDate: date(2026, 10, 5), cycleLength: 28)
        XCTAssertFalse(report(events: current).hasEnoughData, "a running cycle is not a completed one")
        XCTAssertFalse(report(events: current, blocks: [block(start: date(2026, 9, 7), length: 28)]).hasEnoughData,
                       "one completed cycle is not enough")
        XCTAssertFalse(report(blocks: [block(start: date(2026, 8, 10), length: 28),
                                       block(start: date(2026, 9, 7), length: 28)]).hasEnoughData,
                       "the last archived block has no next period start, so only one cycle is complete")
        XCTAssertTrue(report(events: current, blocks: [block(start: date(2026, 8, 10), length: 28),
                                                       block(start: date(2026, 9, 7), length: 28)]).hasEnoughData)
    }

    func testCycleLengthsAndAveragesFromArchive() throws {
        // Stored out of order: the report lists them oldest first. The running cycle closes the last archived one.
        let blocks = [block(start: date(2026, 8, 11), length: 30),
                      block(start: date(2026, 7, 14), length: 28),
                      block(start: date(2026, 9, 10), length: 26)]
        let current = CycleGenerator.events(startDate: date(2026, 10, 6), cycleLength: 28)
        let r = report(events: current, blocks: blocks)
        XCTAssertEqual(r.cycleLengths, [28, 30, 26])
        XCTAssertEqual(r.cycleStarts, [date(2026, 7, 14), date(2026, 8, 11), date(2026, 9, 10)])
        XCTAssertEqual(try XCTUnwrap(r.averageCycle), 28, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(r.averagePeriod), 5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(r.variation), 1.633, accuracy: 0.001, "population standard deviation of 28, 30, 26")
        XCTAssertEqual(r.periodStarts, [date(2026, 7, 14), date(2026, 8, 11), date(2026, 9, 10), date(2026, 10, 6)])
        XCTAssertTrue(r.longCycleIndexes.isEmpty)
    }

    func testShortArchivedBlockDoesNotPrintAOneDayCycle() {
        // Archived after logging only the first period day: the old logged-span length was 1.
        let blocks = [block(events: [menstrual(date(2026, 8, 10))]),
                      block(start: date(2026, 9, 7), length: 28)]
        let current = CycleGenerator.events(startDate: date(2026, 10, 5), cycleLength: 28)
        let r = report(events: current, blocks: blocks)
        XCTAssertEqual(r.cycleLengths, [28, 28])
        XCTAssertFalse(r.cycleLengths.contains(1))
        XCTAssertTrue(r.hasEnoughData)
    }

    func testCycleLengthIsStartToStartNotLoggedSpan() throws {
        // Only ten days logged in the first block, but the next period began 30 days after the first.
        let partial = Array(CycleGenerator.events(startDate: date(2026, 8, 10), cycleLength: 28).prefix(10))
        let blocks = [block(events: partial), block(start: date(2026, 9, 9), length: 28)]
        let current = CycleGenerator.events(startDate: date(2026, 10, 7), cycleLength: 28)
        let r = report(events: current, blocks: blocks)
        XCTAssertEqual(r.cycleLengths, [30, 28])
        XCTAssertEqual(try XCTUnwrap(r.averageCycle), 29, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(r.variation), 1, accuracy: 0.001)
    }

    func testRunningCycleHasNoLength() {
        let blocks = [block(start: date(2026, 8, 10), length: 28), block(start: date(2026, 9, 7), length: 28)]
        let current = CycleGenerator.events(startDate: date(2026, 10, 5), cycleLength: 28)
        let r = report(events: current, blocks: blocks)
        XCTAssertEqual(r.cycleLengths.count, 2, "10/5 opens the running cycle; it has no length")
        XCTAssertEqual(r.cycleStarts, [date(2026, 8, 10), date(2026, 9, 7)])
        XCTAssertEqual(report(events: current).cycleLengths, [], "only a running cycle")
    }

    func testBlockWithoutPeriodIsSkippedAndAdjacentStartsAreOneRun() {
        let noPeriod = block(events: [Event(eventType: .follicular, date: date(2026, 8, 25), note: "")])
        // A spotting break inside one period: 9/7, 9/8, then 9/10. One run, one start.
        let split = block(events: [menstrual(date(2026, 9, 7)), menstrual(date(2026, 9, 8)), menstrual(date(2026, 9, 10)),
                                   Event(eventType: .luteal, date: date(2026, 9, 25), note: "")])
        let blocks = [block(start: date(2026, 8, 10), length: 28), noPeriod, split]
        let current = CycleGenerator.events(startDate: date(2026, 10, 5), cycleLength: 28)
        let r = report(events: current, blocks: blocks)
        XCTAssertEqual(r.cycleLengths, [28, 28])
        XCTAssertEqual(r.periodStarts, [date(2026, 8, 10), date(2026, 9, 7), date(2026, 10, 5)])
    }

    func testGapBetweenStartsIsOneLongCycle() {
        // Nothing logged between the February block and June: start to start is one long cycle.
        let blocks = [block(start: date(2026, 2, 2), length: 28), block(start: date(2026, 6, 1), length: 28)]
        let current = CycleGenerator.events(startDate: date(2026, 6, 29), cycleLength: 28)
        let r = report(events: current, blocks: blocks)
        XCTAssertEqual(r.cycleLengths, [119, 28])
        XCTAssertEqual(r.longCycleIndexes, [0])
    }

    func testChartKeepsTheLastSixCyclesWhileAveragesUseAll() throws {
        var blocks: [ArchivedDataBlock] = []
        var start = date(2025, 12, 1)
        for length in [20, 21, 22, 23, 24, 25, 26, 27] {
            blocks.append(block(start: start, length: length))
            start = calendar.date(byAdding: .day, value: length, to: start)!
        }
        let r = report(events: [menstrual(start)], blocks: blocks)
        XCTAssertEqual(r.cycleLengths, [22, 23, 24, 25, 26, 27], "the last six, oldest first")
        XCTAssertEqual(try XCTUnwrap(r.averageCycle), 23.5, accuracy: 0.001, "the average covers every completed cycle")
        XCTAssertEqual(r.periodStarts.count, 9, "every period start is listed, the running cycle's too")
    }

    func testCurrentCyclePeriodStartIsListed() {
        let blocks = [block(start: date(2026, 8, 10), length: 28), block(start: date(2026, 9, 7), length: 28)]
        let current = CycleGenerator.events(startDate: date(2026, 10, 5), cycleLength: 28)
        let r = report(events: current, blocks: blocks)
        XCTAssertEqual(r.periodStarts, [date(2026, 8, 10), date(2026, 9, 7), date(2026, 10, 5)])
        XCTAssertEqual(r.cycleLengths, [28, 28], "the running cycle has no length yet")
    }

    func testLongCycleMarkedOver45() {
        let blocks = [block(start: date(2026, 5, 1), length: 28),
                      block(start: date(2026, 5, 29), length: 50),
                      block(start: date(2026, 7, 18), length: 45)]
        let r = report(events: [menstrual(date(2026, 9, 1))], blocks: blocks)
        XCTAssertEqual(r.cycleLengths, [28, 50, 45])
        XCTAssertEqual(r.longCycleIndexes, [1], "over 45 days is long; exactly 45 is not")
        XCTAssertEqual(DoctorReport.longCycleDays, 45)
    }

    func testTopSymptomsOnlySymptomCategory() {
        let blocks = [block(start: date(2026, 8, 10), length: 28, tags: "Symptom:Cramps, Mood:Irritable, Symptom:Headache"),
                      block(start: date(2026, 9, 7), length: 28, tags: "Symptom:Cramps, Other:Poor Sleep, Menopause:Hot Flashes")]
        var current = CycleGenerator.events(startDate: date(2026, 10, 5), cycleLength: 28)
        current[1].tags = "Symptom:Cramps, Symptom:Bloating, Mood:Irritable"
        current[2].tags = "Symptom:Headache, Symptom:Fatigue, Symptom:Nausea, Symptom:Back Pain, Symptom:Spotting"
        let r = report(events: current, blocks: blocks)

        XCTAssertEqual(r.topSymptoms.count, 6, "up to six")
        XCTAssertEqual(r.topSymptoms.first, SymptomCount(label: "Cramps", count: 3))
        XCTAssertEqual(r.topSymptoms[1], SymptomCount(label: "Headache", count: 2))
        XCTAssertEqual(r.topSymptoms.dropFirst(2).map(\.count), [1, 1, 1, 1], "ties sort by label")
        XCTAssertEqual(r.topSymptoms.dropFirst(2).map(\.label), ["Back Pain", "Bloating", "Fatigue", "Nausea"])
        let labels = r.topSymptoms.map(\.label)
        XCTAssertFalse(labels.contains("Irritable"), "a Mood tag is not a symptom")
        XCTAssertFalse(labels.contains("Poor Sleep"))
        XCTAssertFalse(labels.contains("Hot Flashes"))
    }

    func testMenopauseDataNeverReachesTheCycleReport() {
        let blocks = [block(start: date(2026, 8, 10), length: 28),
                      block(start: date(2026, 9, 7), length: 28),
                      block(start: date(2026, 9, 20), length: 60, mode: .menopause, tags: "Symptom:Cramps")]
        let carrier = Event(eventType: .follicular, date: date(2026, 10, 13), note: "", tags: "Symptom:Cramps, Menopause:Hot Flashes", mode: .menopause)
        let menopausePeriod = Event(eventType: .menstrual, date: date(2026, 9, 25), note: "", mode: .menopause)
        let r = report(events: [carrier, menopausePeriod, menstrual(date(2026, 10, 5))], blocks: blocks)
        XCTAssertEqual(r.cycleLengths, [28, 28], "a menopause block or period day is not a cycle start")
        XCTAssertFalse(r.periodStarts.contains(date(2026, 9, 20)))
        XCTAssertFalse(r.periodStarts.contains(date(2026, 9, 25)))
        XCTAssertTrue(r.longCycleIndexes.isEmpty)
        XCTAssertTrue(r.topSymptoms.isEmpty, "symptoms logged in Menopause mode stay out of the cycle report")
        XCTAssertNil(r.menopause)
        XCTAssertEqual(report(events: [carrier, menstrual(date(2026, 10, 5))], blocks: blocks, mode: .planning).cycleLengths, [28, 28],
                       "Planning reads cycle data")
    }

    // MARK: - Menopause variant

    func testMenopauseVariantUsesMenopauseData() throws {
        let blocks = [block(start: date(2026, 1, 5), length: 28), block(start: date(2026, 2, 2), length: 28)]
        let lastPeriod = Event(eventType: .menstrual, date: date(2026, 3, 14), note: "")
        func carrier(daysAgo: Int, _ tags: String) -> Event {
            Event(eventType: .follicular, date: calendar.date(byAdding: .day, value: -daysAgo, to: today)!, note: "", tags: tags, mode: .menopause)
        }
        let events = [lastPeriod,
                      carrier(daysAgo: 0, "Menopause:Hot Flashes, Menopause:Hot Flashes, Menopause:Night Sweats, Menopause:Poor Sleep"),
                      carrier(daysAgo: 8, "Menopause:Hot Flashes, Other:Poor Sleep"),
                      carrier(daysAgo: 20, "Menopause:Night Sweats")]
        let r = report(events: events, blocks: blocks, mode: .menopause)
        let m = try XCTUnwrap(r.menopause, "Menopause mode builds the variant")
        XCTAssertEqual(m.lastPeriod, date(2026, 3, 14))
        XCTAssertEqual(m.monthsSinceLastPeriod, MenopauseInsights.make(events: events, today: today).monthsSinceLastPeriod)
        XCTAssertEqual(m.monthsSinceLastPeriod, 7)
        XCTAssertEqual(m.hotFlashesPerWeek, [0, 0, 0, 0, 0, 0, 1, 2], "oldest week first; same-day repeats count each")
        XCTAssertEqual(m.nightSweatsPerWeek, [0, 0, 0, 0, 0, 1, 0, 1])
        XCTAssertEqual(m.poorSleepPerWeek, [0, 0, 0, 0, 0, 0, 1, 1], "the older Other:Poor Sleep spelling counts too")
        XCTAssertTrue(m.hasData)

        let text = try pageText(DoctorReportPDFRenderer().render(r, paper: .a4, name: nil, birthDate: nil))
        XCTAssertTrue(text.contains("Months since last period"), text)
        XCTAssertTrue(text.contains("Hot flashes"))
        XCTAssertTrue(text.contains("Night sweats"))
        XCTAssertTrue(text.contains("Poor sleep"))
        XCTAssertTrue(text.contains("Tracking tool, not medical advice."))
        XCTAssertFalse(text.contains("Average cycle"), "the menopause variant has no cycle statistics")
    }

    // MARK: - Page

    func testRendersOnePageWithEmptyStateMessageWhenSparse() throws {
        let r = report(blocks: [block(start: date(2026, 9, 7), length: 28)])
        XCTAssertFalse(r.hasEnoughData)
        let text = try pageText(DoctorReportPDFRenderer().render(r, paper: .letter, name: nil, birthDate: nil))
        XCTAssertTrue(text.contains("Log a few more cycles"), text)
        XCTAssertTrue(text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("Tracking tool, not medical advice."),
                      "the disclaimer is the last line: \(text)")
    }

    func testFullReportListsStatsSymptomsAndPeriodStartsAndEndsWithDisclaimer() throws {
        let blocks = [block(start: date(2026, 7, 13), length: 28, tags: "Symptom:Cramps"),
                      block(start: date(2026, 8, 10), length: 50),
                      block(start: date(2026, 9, 29), length: 26)]
        let r = report(blocks: blocks)
        let text = try pageText(DoctorReportPDFRenderer().render(r, paper: .letter, name: nil, birthDate: nil))
        XCTAssertTrue(text.contains("Average cycle"), text)
        XCTAssertTrue(text.contains("Average period"))
        XCTAssertTrue(text.contains("Cramps"))
        XCTAssertTrue(text.contains("Period start dates"))
        XCTAssertTrue(text.contains("50"), "the long cycle's length is on the chart")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("long"), "a cycle over 45 days is marked long")
        XCTAssertTrue(text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("Tracking tool, not medical advice."))
    }

    func testNameAndBirthDateAreNotWrittenToDefaults() throws {
        let name = "Jane Example-Report"
        let birthDate = date(1988, 4, 23)
        let stores: [UserDefaults] = [.standard, AppGroup.defaults]
        let before = stores.map { $0.dictionaryRepresentation() }

        let r = report(blocks: [block(start: date(2026, 8, 10), length: 28), block(start: date(2026, 9, 7), length: 28)])
        let text = try pageText(DoctorReportPDFRenderer().render(r, paper: .letter, name: name, birthDate: birthDate))
        XCTAssertTrue(text.contains(name), "the name is printed on the page")
        XCTAssertTrue(text.contains("1988"), "the birth date is printed on the page")

        for (index, store) in stores.enumerated() {
            let after = store.dictionaryRepresentation()
            XCTAssertEqual(Set(before[index].keys), Set(after.keys), "rendering adds no key to the defaults")
            for (key, value) in after {
                let dump = "\(key) \(value)"
                XCTAssertFalse(dump.contains(name), "the name is never stored (\(key))")
                XCTAssertFalse(dump.contains("1988-04-23"), "the birth date is never stored (\(key))")
            }
        }
    }
}
