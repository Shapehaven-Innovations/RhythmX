import XCTest
@testable import RhythmX

/// Task 20: the pure planner behind Apple Calendar sync. Which items exist for which options, the discreet
/// titles, the diff against what is already in the "RhythmX" calendar, and the mode and prediction rules.
@MainActor
final class CalendarSyncDiffTests: XCTestCase {
    private let calendar = Calendar.current
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 5, day: 1))!
    private func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: anchor)! }
    private func key(_ n: Int) -> String { FertileWindow.dayKey(day(n), calendar: calendar) }

    /// A generated 28-day cycle from the anchor: menstrual 0...4, follicular 5...12, ovulation 13...15, luteal 16...27.
    private var cycle: [Event] { CycleGenerator.events(startDate: anchor, cycleLength: 28) }
    private let all = SyncOptions(periodDays: true, predictedPeriod: true, fertileWindow: true, phaseStarts: true)
    private let none = SyncOptions(periodDays: false, predictedPeriod: false, fertileWindow: false, phaseStarts: false)

    private func items(_ events: [Event], blocks: [ArchivedDataBlock] = [], options: SyncOptions? = nil,
                       discreet: Bool = false, symbols: DiscreetSymbols = .default, today: Int = 10,
                       overrides: FertileOverrides = FertileOverrides()) -> [SyncItem] {
        CalendarSyncPlanner.items(events: events, archivedBlocks: blocks, options: options ?? all, discreet: discreet,
                                  symbols: symbols, today: day(today), overrides: overrides, calendar: calendar)
    }

    // MARK: - Options

    func testItemsRespectOptions() {
        let everything = items(cycle)
        XCTAssertTrue(everything.contains { $0.key.hasPrefix("period-") })
        XCTAssertTrue(everything.contains { $0.key.hasPrefix("predicted-") })
        XCTAssertTrue(everything.contains { $0.key.hasPrefix("fertile-") })
        XCTAssertTrue(everything.contains { $0.key.hasPrefix("phase-") })

        var only = none
        only.periodDays = true
        XCTAssertEqual(items(cycle, options: only).map(\.key), ["period-\(key(0))-\(key(4))"],
                       "period days merge into one all-day run")

        only = none; only.fertileWindow = true
        XCTAssertEqual(items(cycle, options: only).map(\.key), ["fertile-\(key(8))-\(key(15))"])

        only = none; only.phaseStarts = true
        XCTAssertEqual(items(cycle, options: only).map(\.key),
                       ["phase-follicular-\(key(5))", "phase-ovulation-\(key(13))", "phase-luteal-\(key(16))"],
                       "the period start is already the period event, so only the other three phases")

        XCTAssertTrue(items(cycle, options: none).isEmpty)
    }

    func testRunsAreAllDayAndInclusive() {
        var only = none
        only.periodDays = true
        let period = items(cycle, options: only)[0]
        XCTAssertTrue(period.isAllDay)
        XCTAssertEqual(period.start, day(0))
        XCTAssertEqual(period.end, day(4), "the last day, inclusive")

        let later = CycleGenerator.events(startDate: day(28), cycleLength: 28)
        XCTAssertEqual(items(cycle + later, options: only).map(\.key),
                       ["period-\(key(0))-\(key(4))", "period-\(key(28))-\(key(32))"], "one run per period")
    }

    func testFertileWindowHonorsOverrides() {
        var only = none
        only.fertileWindow = true
        let overrides = FertileOverrides(added: [key(7)], removed: [key(15)])
        XCTAssertEqual(items(cycle, options: only, overrides: overrides).map(\.key), ["fertile-\(key(7))-\(key(14))"])
    }

    // MARK: - Titles

    func testDiscreetTitles() {
        let plain = items(cycle)
        XCTAssertEqual(Set(plain.map(\.title)),
                       ["Period", "Predicted period", "Fertile window",
                        "Follicular phase starts", "Ovulation phase starts", "Luteal phase starts"])

        let discreet = items(cycle, discreet: true)
        XCTAssertEqual(discreet.map(\.key), plain.map(\.key), "the same items, only the titles change")
        XCTAssertEqual(Set(discreet.map(\.title)), Set(CalendarSyncTitles.discreet.values))
        XCTAssertEqual(Set(CalendarSyncTitles.discreet.values), ["R", "F", "P"], "the one placeholder table")
        XCTAssertEqual(discreet.first { $0.key.hasPrefix("period-") }?.title, "R")
        XCTAssertEqual(discreet.first { $0.key.hasPrefix("fertile-") }?.title, "F")
        XCTAssertEqual(discreet.first { $0.key.hasPrefix("phase-") }?.title, "P")
        for title in discreet.map(\.title) {
            XCTAssertFalse(title.lowercased().contains("period"))
            XCTAssertFalse(title.lowercased().contains("fertile"))
        }
    }

    // MARK: - Custom discreet symbols

    func testDiscreetSymbolsSanitize() {
        XCTAssertEqual(DiscreetSymbols.default, DiscreetSymbols(period: "R", fertileWindow: "F", phaseStart: "P"))
        XCTAssertEqual(DiscreetSymbols(period: "", fertileWindow: "   ", phaseStart: "\n").period, "R", "empty falls back")
        XCTAssertEqual(DiscreetSymbols(period: "", fertileWindow: "   ", phaseStart: "\n").fertileWindow, "F")
        XCTAssertEqual(DiscreetSymbols(period: "", fertileWindow: "   ", phaseStart: "\n").phaseStart, "P")

        XCTAssertEqual(DiscreetSymbols.clean("  x "), "x", "whitespace is trimmed")
        XCTAssertEqual(DiscreetSymbols.clean("ABC"), "AB", "at most two characters")
        XCTAssertEqual(DiscreetSymbols.clean("7"), "7")
        XCTAssertEqual(DiscreetSymbols.clean("a1"), "a1")
        XCTAssertEqual(DiscreetSymbols.clean("Mo"), "Mo")
        XCTAssertEqual(DiscreetSymbols.clean("🌙"), "🌙", "a single emoji")
        XCTAssertEqual(DiscreetSymbols.clean("👩‍👩‍👧"), "👩‍👩‍👧", "a joined emoji counts as one")
        XCTAssertEqual(DiscreetSymbols.clean("❤️"), "❤️")
        XCTAssertEqual(DiscreetSymbols.clean("🌙🌙"), "🌙", "only one emoji")
        XCTAssertEqual(DiscreetSymbols.clean("🌙a"), "🌙", "an emoji stands alone")
        XCTAssertEqual(DiscreetSymbols.clean("!?"), "", "only letters, digits or an emoji")
        XCTAssertEqual(DiscreetSymbols.clean("a b"), "ab")
        XCTAssertEqual(DiscreetSymbols(period: "!!", fertileWindow: "Fertile", phaseStart: "🌗").period, "R")
        XCTAssertEqual(DiscreetSymbols(period: "!!", fertileWindow: "Fertile", phaseStart: "🌗").fertileWindow, "Fe")
        XCTAssertEqual(DiscreetSymbols(period: "!!", fertileWindow: "Fertile", phaseStart: "🌗").phaseStart, "🌗")
    }

    func testDiscreetTitlesUseCustomSymbols() {
        let symbols = DiscreetSymbols(period: "🌙", fertileWindow: "X", phaseStart: "7")
        let custom = items(cycle, discreet: true, symbols: symbols)
        XCTAssertEqual(custom.first { $0.key.hasPrefix("period-") }?.title, "🌙")
        XCTAssertEqual(custom.first { $0.key.hasPrefix("predicted-") }?.title, "🌙", "the predicted period uses the period symbol")
        XCTAssertEqual(custom.first { $0.key.hasPrefix("fertile-") }?.title, "X")
        XCTAssertEqual(Set(custom.filter { $0.key.hasPrefix("phase-") }.map(\.title)), ["7"])

        XCTAssertEqual(items(cycle, discreet: false, symbols: symbols).map(\.title), items(cycle).map(\.title),
                       "symbols only apply to discreet titles")
        XCTAssertEqual(items(cycle, discreet: true).map(\.title), items(cycle, discreet: true, symbols: .default).map(\.title))
    }

    func testSymbolChangeIsRemovePlusAdd() {
        var only = none
        only.periodDays = true
        let before = Set(items(cycle, options: only, discreet: true))
        let after = Set(items(cycle, options: only, discreet: true,
                              symbols: DiscreetSymbols(period: "Z", fertileWindow: "", phaseStart: "")))
        let diff = CalendarSyncPlanner.diff(existing: before, desired: after)
        XCTAssertEqual(diff.remove.map(\.title), ["R"])
        XCTAssertEqual(diff.add.map(\.title), ["Z"])
        XCTAssertEqual(diff.add.map(\.key), diff.remove.map(\.key))
    }

    func testEventNotesAndURLCarryNoMeaning() {
        for item in items(cycle) {
            let stored = CalendarSync.storedKey(for: item.key)
            XCTAssertEqual(stored, CalendarSync.storedKey(for: item.key), "stable across syncs")
            let notes = CalendarSync.notes(forStoredKey: stored)
            let url = CalendarSync.url(forStoredKey: stored)?.absoluteString ?? ""
            for text in [notes, url] {
                for word in ["period", "predicted", "fertile", "phase", "follicular", "ovulation", "luteal", "2024"] {
                    XCTAssertFalse(text.lowercased().contains(word), "\(text) must not reveal \(word)")
                }
            }
            XCTAssertEqual(CalendarSync.storedKey(fromNotes: notes, url: nil), stored)
            XCTAssertEqual(CalendarSync.storedKey(fromNotes: nil, url: URL(string: url)), stored)
        }
        XCTAssertEqual(Set(items(cycle).map { CalendarSync.storedKey(for: $0.key) }).count, items(cycle).count)
    }

    // MARK: - Diff

    func testDiffAddsNewAndRemovesStale() {
        let a = SyncItem(key: "period-a", title: "Period", start: day(0), end: day(4), isAllDay: true)
        let b = SyncItem(key: "fertile-b", title: "Fertile window", start: day(8), end: day(15), isAllDay: true)
        let bRenamed = SyncItem(key: "fertile-b", title: "F", start: day(8), end: day(15), isAllDay: true)
        let c = SyncItem(key: "phase-c", title: "Luteal phase starts", start: day(16), end: day(16), isAllDay: true)

        let diff = CalendarSyncPlanner.diff(existing: [a, b], desired: [a, bRenamed, c])

        XCTAssertEqual(Set(diff.add), [bRenamed, c], "a changed title is a new event")
        XCTAssertEqual(Set(diff.remove), [b], "the old version goes, the unchanged one stays")

        let same = CalendarSyncPlanner.diff(existing: [a, b, c], desired: [a, b, c])
        XCTAssertTrue(same.add.isEmpty)
        XCTAssertTrue(same.remove.isEmpty)

        let gone = CalendarSyncPlanner.diff(existing: [a, b, c], desired: [])
        XCTAssertEqual(Set(gone.remove), [a, b, c], "turning everything off removes every app event")
    }

    // MARK: - Modes

    func testNoItemsFromMenopauseEvents() {
        let menopause = [
            Event(id: "m1", eventType: .menstrual, date: day(40), note: "", tags: "Symptom:Spotting", mode: .menopause),
            Event(id: "m2", eventType: .ovulation, date: day(45), note: "", mode: .menopause),
            Event(id: "m3", eventType: .follicular, date: day(46), note: "", tags: "Menopause:Hot Flashes", mode: .menopause),
        ]
        XCTAssertTrue(items(menopause).isEmpty)

        let block = ArchivedDataBlock(date: day(-1), groupedEvents: [
            .init(eventType: .menstrual, events: [Event(eventType: .menstrual, date: day(-28), note: "", mode: .menopause)])
        ], mode: .menopause)
        XCTAssertTrue(items(menopause, blocks: [block]).isEmpty, "a Menopause archive never predicts a period")

        XCTAssertEqual(items(cycle + menopause).map(\.key), items(cycle).map(\.key),
                       "Menopause events alongside a cycle change nothing")
    }

    // MARK: - Prediction

    private func archivedCycle(startingAt start: Int) -> ArchivedDataBlock {
        let events = CycleGenerator.events(startDate: day(start), cycleLength: 28)
        let grouped = Event.EventType.allCases.map { type in
            ArchivedDataBlock.PhaseEvents(eventType: type, events: events.filter { $0.eventType == type })
        }
        return ArchivedDataBlock(date: day(start + 27), groupedEvents: grouped, mode: .cycle)
    }

    func testPredictedPeriodUsesPredictionService() {
        var only = none
        only.predictedPeriod = true
        let blocks = [archivedCycle(startingAt: -56), archivedCycle(startingAt: -28)]
        let predicted = CyclePredictionService.predictedStartDate(from: blocks)!
        XCTAssertEqual(calendar.startOfDay(for: predicted), day(0), "sanity: the service predicts the anchor day")

        // No current cycle: the archive prediction is the item, when it is still ahead.
        let ahead = items([], blocks: blocks, options: only, today: -3)
        XCTAssertEqual(ahead.map(\.key), ["predicted-\(key(0))"])
        XCTAssertEqual(ahead[0].start, day(0))
        XCTAssertEqual(ahead[0].end, day(0))
        XCTAssertTrue(ahead[0].isAllDay)

        XCTAssertTrue(items([], blocks: blocks, options: only, today: 3).isEmpty, "a prediction in the past is not synced")

        // With a current cycle the estimate follows it (start plus span), as the Calendar tab's dashed day does.
        XCTAssertEqual(items(cycle, blocks: blocks, options: only, today: 10).map(\.key), ["predicted-\(key(28))"])
        XCTAssertTrue(items([], blocks: [], options: only).isEmpty, "nothing to predict from")
    }
}
