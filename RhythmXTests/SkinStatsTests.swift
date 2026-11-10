//  SkinStatsTests.swift
//  Task 5: skin statistics by cycle phase.

import XCTest
@testable import RhythmX

final class SkinStatsTests: XCTestCase {
    private let cal = Calendar.current
    private let base = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    private var farFuture: Date { cal.date(byAdding: .day, value: 400, to: base)! }

    private func at(_ offset: Int, from start: Date? = nil) -> Date {
        cal.date(byAdding: .day, value: offset, to: start ?? base)!
    }

    /// A 28-day cycle from `start` (CycleGenerator), with `tags[offset]` set on that day's event.
    private func cycle(start: Date, length: Int = 28, tags: [Int: String] = [:], mode: TrackingMode? = nil) -> [Event] {
        CycleGenerator.events(startDate: start, cycleLength: length).enumerated().map { i, e in
            var e = e
            e.tags = tags[i] ?? ""
            e.mode = mode
            return e
        }
    }

    /// `count` consecutive days of `phase` from `offset`, the first `flares` tagged `flare`, the rest `other`.
    private func run(_ phase: Event.EventType, from offset: Int, count: Int, flares: Int,
                     flare: String = "Skin:Chin/Acne", other: String = "Skin:Chin/Clear") -> [Event] {
        (0..<count).map { i in
            Event(eventType: phase, date: at(offset + i), note: "", tags: i < flares ? flare : other)
        }
    }

    private func block(_ events: [Event], mode: TrackingMode? = .cycle) -> ArchivedDataBlock {
        let grouped = Event.EventType.allCases.map { t in
            ArchivedDataBlock.PhaseEvents(eventType: t, events: events.filter { $0.eventType == t })
        }
        return ArchivedDataBlock(date: events.last?.date ?? base, groupedEvents: grouped, mode: mode)
    }

    private func stats(_ events: [Event], blocks: [ArchivedDataBlock] = [], today: Date? = nil,
                       window: SkinStats.Window = .all, kinds: Set<SkinTag.Kind>? = nil) -> SkinStats {
        SkinStats(events: events, archivedBlocks: blocks, today: today ?? farFuture, window: window, kinds: kinds, calendar: cal)
    }

    private func cell(_ s: SkinStats, _ area: SkinTag.Area, _ phase: Event.EventType) -> SkinStats.PhaseCell? {
        s.rows().first { $0.area == area }?.cells.first { $0.phase == phase }
    }

    private func assertClean(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let lower = text.lowercased()
        for word in SkinStats.bannedWords {
            XCTAssertFalse(lower.contains(word), "\"\(text)\" contains \(word)", file: file, line: line)
        }
    }

    // MARK: Logged days and percentages

    func testLoggedDaysCountSkinAndLegacyAcneOnce() {
        let events = cycle(start: base, tags: [20: "Skin:Chin/Acne, Skin:Back/Dry", 21: "Other:Acne", 22: "Symptom:Cramps"])
        let s = stats(events)
        XCTAssertEqual(s.loggedDays, 2)
        XCTAssertEqual(s.loggedDaysByPhase[.luteal], 2)
    }

    func testPercentUsesLoggedDaysNotPhaseDays() {
        // 26-day cycle: luteal is offsets 16..<26, ten days. Four logged, two chin flares.
        let events = cycle(start: base, length: 26, tags: [
            16: "Skin:Chin/Acne", 17: "Skin:Chin/Breakout", 18: "Skin:Chin/Clear", 19: "Skin:Back/Clear"
        ])
        let s = stats(events)
        let c = cell(s, .chin, .luteal)
        XCTAssertEqual(c?.loggedDays, 4)
        XCTAssertEqual(c?.flareDays, 2)
        XCTAssertEqual(c?.percent, 50)
        XCTAssertEqual(s.percentByArea(phase: .luteal)[.chin], .some(50))
    }

    func testCellBelowMinimumIsNil() {
        let events = cycle(start: base, tags: [5: "Skin:Chin/Acne", 6: "Skin:Chin/Clear"])
        let s = stats(events)
        let c = cell(s, .chin, .follicular)
        XCTAssertEqual(c?.loggedDays, 2)
        XCTAssertNil(c?.percent)
        XCTAssertEqual(s.percentByArea(phase: .follicular)[.chin], .some(nil))
        XCTAssertEqual(s.percentByArea(phase: nil)[.chin], .some(nil), "under minimumDaysForBody overall")
    }

    func testClearIsNotAFlare() {
        let events = cycle(start: base, tags: [16: "Skin:Chin/Clear", 17: "Skin:Chin/Clear", 18: "Skin:Face/Clear"])
        let s = stats(events)
        XCTAssertEqual(s.loggedDays, 3)
        XCTAssertTrue(s.rows().isEmpty)
        XCTAssertEqual(s.percentByArea(phase: .luteal)[.chin], .some(0))
    }

    func testKindFilterMatchesAnyKind() {
        let tags = [16: "Skin:Chin/Acne+Breakout", 17: "Skin:Chin/Acne+Breakout", 18: "Skin:Chin/Acne+Breakout"]
        let acne = stats(cycle(start: base, tags: tags), kinds: SkinStats.KindFilter.acneBreakout.kinds)
        XCTAssertEqual(cell(acne, .chin, .luteal)?.percent, 100)
        let oily = stats(cycle(start: base, tags: tags), kinds: SkinStats.KindFilter.oily.kinds)
        XCTAssertTrue(oily.rows().isEmpty)
        XCTAssertEqual(oily.loggedDays, 3)
    }

    func testLegacyAcneCountsAsFaceAcneUnderAcneFilterOnly() {
        let tags = [16: "Other:Acne", 17: "Other:Acne", 18: "Other:Acne"]
        let any = stats(cycle(start: base, tags: tags))
        XCTAssertEqual(cell(any, .face, .luteal)?.percent, 100)
        XCTAssertEqual(any.rows().first?.topKind, .acne)
        let acne = stats(cycle(start: base, tags: tags), kinds: SkinStats.KindFilter.acneBreakout.kinds)
        XCTAssertEqual(cell(acne, .face, .luteal)?.percent, 100)
        let dry = stats(cycle(start: base, tags: tags), kinds: SkinStats.KindFilter.dryFlaky.kinds)
        XCTAssertTrue(dry.rows().isEmpty)
        XCTAssertEqual(dry.loggedDays, 3)
    }

    func testKindFilterVerbsAndKinds() {
        XCTAssertEqual(SkinStats.KindFilter.acneBreakout.kinds, [.acne, .breakout])
        XCTAssertEqual(SkinStats.KindFilter.dryFlaky.kinds, [.dry, .flaky])
        XCTAssertEqual(SkinStats.KindFilter.acneBreakout.verb, "breaks out")
        XCTAssertEqual(SkinStats.KindFilter.dryFlaky.verb, "is dry")
        XCTAssertEqual(SkinStats.KindFilter.oily.verb, "is oily")
        XCTAssertEqual(SkinStats.KindFilter.irritated.verb, "is irritated")
    }

    // MARK: Peak and order

    func testPeakSetAndTies() {
        let single = stats(run(.luteal, from: 0, count: 3, flares: 3) + run(.follicular, from: 10, count: 3, flares: 0))
        XCTAssertEqual(single.rows().first?.peak, [.luteal])

        let tie = stats(run(.luteal, from: 0, count: 3, flares: 3) + run(.follicular, from: 10, count: 3, flares: 3))
        XCTAssertEqual(tie.rows().first?.peak, [.luteal, .follicular])

        let lone = stats(run(.luteal, from: 0, count: 3, flares: 3) + run(.follicular, from: 10, count: 2, flares: 1))
        XCTAssertEqual(lone.rows().first?.peak, [])
        XCTAssertEqual(lone.rows().first?.maxPercent, 100)
    }

    func testRowsSortedByMaxPercentFaceLast() {
        let events = (0..<4).map { i -> Event in
            var tags = ["Skin:Face/Acne"]
            if i < 2 { tags.append("Skin:Chin/Acne") }
            if i < 3 { tags.append("Skin:Back/Breakout") }
            return Event(eventType: .luteal, date: at(i), note: "", tags: tags.joined(separator: ", "))
        }
        let rows = stats(events).rows()
        XCTAssertEqual(rows.map(\.area), [.back, .chin, .face])
        XCTAssertEqual(rows.map(\.maxPercent), [75, 50, 100])
        XCTAssertEqual(stats(events).topAreas(limit: 2).map(\.area), [.back, .chin])
    }

    // MARK: Window, menopause, cycles

    func testWindowExcludesFutureAndOlderDays() {
        let today = at(100)
        let events = [0, -29, -30, 1].map {
            Event(eventType: .luteal, date: at(100 + $0), note: "", tags: "Skin:Chin/Acne")
        }
        XCTAssertEqual(stats(events, today: today, window: .thirty).loggedDays, 2)
        XCTAssertEqual(stats(events, today: today, window: .all).loggedDays, 3)
    }

    func testMenopauseEventsNeverSupplyAPhase() {
        let live = run(.luteal, from: 0, count: 3, flares: 3).map { e -> Event in var e = e; e.mode = .menopause; return e }
        let archived = block(run(.follicular, from: 10, count: 3, flares: 3), mode: .menopause)
        let s = stats(live, blocks: [archived])
        XCTAssertEqual(s.loggedDays, 6)
        XCTAssertTrue(s.loggedDaysByPhase.values.allSatisfy { $0 == 0 })
        XCTAssertTrue(s.rows().first?.cells.allSatisfy { $0.percent == nil } ?? false)
        XCTAssertEqual(s.percentByArea(phase: nil)[.chin], .some(100))
        XCTAssertEqual(s.percentByArea(phase: .luteal)[.chin], .some(nil))
        XCTAssertEqual(s.cyclesCovered, 0)
    }

    func testCyclesCoveredAndHasPhaseData() {
        let past = block(cycle(start: base, tags: [16: "Skin:Chin/Acne"]))
        let live = cycle(start: at(28), tags: [3: "Skin:Chin/Acne"])
        let both = stats(live, blocks: [past])
        XCTAssertEqual(both.cyclesCovered, 2)
        XCTAssertTrue(both.hasPhaseData)

        let liveOnly = stats(live)
        XCTAssertEqual(liveOnly.cyclesCovered, 1)
        XCTAssertFalse(liveOnly.hasPhaseData)

        let menoBlock = block(cycle(start: at(-60), tags: [3: "Skin:Chin/Acne"]), mode: .menopause)
        XCTAssertEqual(stats(live, blocks: [menoBlock]).cyclesCovered, 1)

        let untagged = block(cycle(start: base))
        XCTAssertEqual(stats(live, blocks: [untagged]).cyclesCovered, 1)
    }

    // MARK: Sentence

    /// Two cycles: follicular days clear, luteal days with `luteal` tags. Four logged days per phase in all.
    private func twoCycles(luteal: String) -> (events: [Event], blocks: [ArchivedDataBlock]) {
        let tags = [5: "Skin:Chin/Clear", 6: "Skin:Chin/Clear", 18: luteal, 19: luteal]
        return (cycle(start: at(28), tags: tags), [block(cycle(start: base, tags: tags))])
    }

    func testSentenceTemplatesAndBannedWords() {
        var outputs: [String] = []

        let two = twoCycles(luteal: "Skin:Chin/Acne, Skin:Back/Breakout")
        let s2 = stats(two.events, blocks: two.blocks)
        let withDay = s2.sentence(todayPhase: .luteal, cycleDay: 20, mode: .cycle)
        XCTAssertEqual(withDay, "Your chin and back tend to flare in the luteal phase. Today is luteal day 20.")
        let noPhase = s2.sentence(todayPhase: nil, cycleDay: nil, mode: .planning)
        XCTAssertEqual(noPhase, "Your chin and back tend to flare in the luteal phase.")
        outputs += [withDay, noPhase]

        let one = twoCycles(luteal: "Skin:Chin/Acne")
        let s1 = stats(one.events, blocks: one.blocks)
        let oneArea = s1.sentence(todayPhase: .follicular, cycleDay: 7, mode: .cycle)
        XCTAssertEqual(oneArea, "Your chin tends to flare in the luteal phase. Today is follicular day 7.")
        outputs.append(oneArea)

        let meno = stats(two.events, blocks: two.blocks, today: at(60), window: .ninety)
            .sentence(todayPhase: nil, cycleDay: nil, mode: .menopause)
        XCTAssertEqual(meno, "Your chin and back have flared most over the last 90 days.")
        let menoOne = stats(one.events, blocks: one.blocks, today: at(60), window: .ninety)
            .sentence(todayPhase: nil, cycleDay: nil, mode: .menopause)
        XCTAssertEqual(menoOne, "Your chin has flared most over the last 90 days.")
        outputs += [meno, menoOne]

        let first = stats(two.events).sentence(todayPhase: .luteal, cycleDay: 20, mode: .cycle)
        XCTAssertEqual(first, "Log your skin through two cycles and this card shows where it tends to flare. 1 of 2 so far.")
        let none = stats([]).sentence(todayPhase: nil, cycleDay: nil, mode: .cycle)
        XCTAssertEqual(none, "Log your skin through two cycles and this card shows where it tends to flare. 0 of 2 so far.")
        let menoEmpty = stats([]).sentence(todayPhase: nil, cycleDay: nil, mode: .menopause)
        XCTAssertFalse(menoEmpty.isEmpty)
        outputs += [first, none, menoEmpty]

        let clear = twoCycles(luteal: "Skin:Chin/Clear")
        let flat = stats(clear.events, blocks: clear.blocks).sentence(todayPhase: .luteal, cycleDay: 20, mode: .cycle)
        XCTAssertFalse(flat.isEmpty)
        outputs.append(flat)

        outputs.forEach { assertClean($0) }
    }

    // MARK: Headline and comparison

    func testHeadlineRatioRules() {
        let acne = SkinStats.KindFilter.acneBreakout
        let strong = stats(run(.luteal, from: 0, count: 50, flares: 31) + run(.follicular, from: 100, count: 10, flares: 1),
                           kinds: acne.kinds)
        let h = strong.headline(area: .chin, filter: acne)
        XCTAssertEqual(h?.title, "Chin breaks out 6× more in luteal")
        XCTAssertEqual(h?.detail, "62% of luteal days vs 10% of follicular days")

        let mild = stats(run(.luteal, from: 0, count: 10, flares: 3) + run(.follicular, from: 100, count: 50, flares: 9),
                         kinds: acne.kinds)
        XCTAssertEqual(mild.headline(area: .chin, filter: acne)?.title, "Chin breaks out more in luteal")

        let same = stats(run(.luteal, from: 0, count: 10, flares: 2) + run(.follicular, from: 100, count: 50, flares: 9),
                         kinds: acne.kinds)
        XCTAssertEqual(same.headline(area: .chin, filter: acne)?.title, "Chin looks about the same across your phases.")

        let zero = stats(run(.luteal, from: 0, count: 3, flares: 3) + run(.follicular, from: 100, count: 3, flares: 0))
        XCTAssertNil(zero.headline(area: .chin, filter: acne))

        let thin = stats(run(.luteal, from: 0, count: 3, flares: 3) + run(.follicular, from: 100, count: 2, flares: 1))
        XCTAssertNil(thin.headline(area: .chin, filter: acne))

        let dry = SkinStats.KindFilter.dryFlaky
        let dryStats = stats(run(.luteal, from: 0, count: 50, flares: 31, flare: "Skin:Chin/Dry")
                             + run(.follicular, from: 100, count: 10, flares: 1, flare: "Skin:Chin/Dry"), kinds: dry.kinds)
        XCTAssertEqual(dryStats.headline(area: .chin, filter: dry)?.title, "Chin is dry 6× more in luteal")

        [h?.title, h?.detail].compactMap { $0 }.forEach { assertClean($0) }
    }

    func testComparisonLine() {
        let s = stats(run(.luteal, from: 0, count: 50, flares: 31, flare: "Skin:Chin/Acne/Red")
                      + run(.follicular, from: 100, count: 10, flares: 1))
        let line = s.comparisonLine(area: .chin)
        XCTAssertEqual(line, "Chin 62% in luteal vs 10% in follicular. Mostly acne, red.")
        XCTAssertEqual(s.rows().first?.topColour, .red)
        line.map { assertClean($0) }

        let thin = stats(run(.luteal, from: 0, count: 3, flares: 3) + run(.follicular, from: 100, count: 2, flares: 0))
        XCTAssertNil(thin.comparisonLine(area: .chin))
    }

    // MARK: Intimacy

    func testIntimacyByPhaseCountsSexOrIntercourseOnce() {
        let events = [
            Event(eventType: .luteal, date: at(0), note: "", tags: "Intimacy:Sex, Planning:Intercourse"),
            Event(eventType: .luteal, date: at(1), note: "", tags: "Planning:Intercourse"),
            Event(eventType: .luteal, date: at(2), note: "", tags: "Symptom:Cramps"),
            Event(eventType: .luteal, date: at(3), note: "", tags: ""),
            Event(eventType: .follicular, date: at(10), note: "", tags: "Intimacy:Sex"),
        ]
        let cells = stats(events).intimacyByPhase()
        XCTAssertEqual(cells.map(\.phase), Event.EventType.allCases)
        let luteal = cells.first { $0.phase == .luteal }
        XCTAssertEqual(luteal?.loggedDays, 3)
        XCTAssertEqual(luteal?.flareDays, 2)
        XCTAssertEqual(luteal?.percent, 67)
        XCTAssertNil(cells.first { $0.phase == .follicular }?.percent)
    }

    func testIntimacySkinLineNeedsFiveDaysEachSide() {
        func day(_ i: Int, sex: Bool, flare: Bool) -> Event {
            var tags = [flare ? "Skin:Chin/Acne" : "Skin:Chin/Clear"]
            if sex { tags.append("Intimacy:Sex") }
            return Event(eventType: .luteal, date: at(i), note: "", tags: tags.joined(separator: ", "))
        }
        var events = (0..<5).map { day($0, sex: true, flare: $0 < 3) }
        events += (5..<9).map { day($0, sex: false, flare: $0 == 5) }
        XCTAssertNil(stats(events).intimacySkinLine())

        events.append(day(9, sex: false, flare: false))
        let line = stats(events).intimacySkinLine()
        XCTAssertEqual(line, "On days with sex logged, skin flared on 60% of logged days; on other logged days, 20%.")
        line.map { assertClean($0) }
    }
}
