//  SkinStoreRulesTests.swift
//  Task 4: store rules, phase lookup, exclusions for skin and intimacy tags.

import XCTest
@testable import RhythmX

@MainActor
final class SkinStoreRulesTests: XCTestCase {
    private let cal = Calendar.current
    private func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: d))! }
    private func skin(_ area: SkinTag.Area, _ kinds: Set<SkinTag.Kind>, _ colour: SkinTag.Colour? = nil) -> SkinTag {
        SkinTag(area: area, kinds: kinds, colour: colour)!
    }
    private func tags(_ store: EventStore, on d: Date) -> [String] {
        store.events.filter { $0.date.startOfDay == d.startOfDay }.flatMap { TagParser.split($0.tags) }
    }

    // MARK: Sex / Intercourse equivalence

    func testSexAndIntercourseAreDuplicatesOfEachOther() {
        let a = EventStore(preview: true)
        a.add(Event(eventType: .follicular, date: day(5), note: "", tags: "Planning:Intercourse"))
        XCTAssertTrue(a.isDuplicateTag("Intimacy:Sex", on: day(5)))
        XCTAssertFalse(a.logTag("Intimacy:Sex", on: day(5), mode: .cycle))

        let b = EventStore(preview: true)
        b.add(Event(eventType: .follicular, date: day(5), note: "", tags: "Intimacy:Sex"))
        XCTAssertTrue(b.isDuplicateTag("Planning:Intercourse", on: day(5)))
        XCTAssertFalse(b.logTag("Planning:Intercourse", on: day(5), mode: .planning))
    }

    func testQuickLogWriterRefusesSexWhenIntercourseLogged() {
        var events = [Event(eventType: .follicular, date: day(5), note: "", tags: "Planning:Intercourse")]
        XCTAssertFalse(QuickLogWriter.append(category: .intimacy, value: "Sex", to: &events, on: day(5), mode: .cycle))
        XCTAssertEqual(events[0].tags, "Planning:Intercourse")

        var other = [Event(eventType: .follicular, date: day(5), note: "", tags: "Intimacy:Sex")]
        XCTAssertFalse(QuickLogWriter.append(category: .planning, value: "Intercourse", to: &other, on: day(5), mode: .planning))
        XCTAssertEqual(other[0].tags, "Intimacy:Sex")
    }

    // MARK: logSkinTag

    func testLogSkinTagReplacesSameAreaSameDay() {
        let s = EventStore(preview: true)
        s.add(Event(eventType: .follicular, date: day(5), note: ""))
        XCTAssertTrue(s.logSkinTag(skin(.chin, [.dry]), on: day(5), mode: .cycle))
        let second = skin(.chin, [.acne, .breakout], .red)
        XCTAssertTrue(s.logSkinTag(second, on: day(5), mode: .cycle))
        let skins = tags(s, on: day(5)).filter { $0.hasPrefix("Skin:") }
        XCTAssertEqual(skins, [second.raw])
    }

    func testLogSkinTagKeepsOtherAreasAndLegacyAcne() {
        let s = EventStore(preview: true)
        s.add(Event(eventType: .follicular, date: day(5), note: "", tags: "Other:Acne, Skin:Back/Breakout"))
        XCTAssertTrue(s.logSkinTag(skin(.chin, [.acne]), on: day(5), mode: .cycle))
        let t = tags(s, on: day(5))
        XCTAssertTrue(t.contains("Other:Acne"))
        XCTAssertTrue(t.contains("Skin:Back/Breakout"))
        XCTAssertTrue(t.contains("Skin:Chin/Acne"))
    }

    // MARK: phaseByDay

    private func block(_ events: [Event], mode: TrackingMode?) -> ArchivedDataBlock {
        let grouped = Dictionary(grouping: events) { $0.eventType }
            .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) }
        return ArchivedDataBlock(date: day(28), groupedEvents: grouped, mode: mode)
    }

    func testPhaseByDayMergesLiveAndArchivedAndSkipsMenopause() {
        let live = [
            Event(eventType: .luteal, date: day(20), note: ""),
            Event(eventType: .follicular, date: day(22), note: "", mode: .menopause),
        ]
        let archived = [block([Event(eventType: .menstrual, date: day(2), note: "")], mode: .cycle),
                        block([Event(eventType: .follicular, date: day(3), note: "", mode: .menopause)], mode: .menopause)]
        let map = CalendarPhaseLookup.phaseByDay(events: live, archivedBlocks: archived)
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map[day(20).startOfDay], .luteal)
        XCTAssertEqual(map[day(2).startOfDay], .menstrual)
    }

    func testPhaseByDayFirstEventWinsLikePhaseOn() {
        let events = [Event(eventType: .ovulation, date: day(10), note: ""),
                      Event(eventType: .luteal, date: day(10), note: "")]
        let map = CalendarPhaseLookup.phaseByDay(events: events, archivedBlocks: [])
        XCTAssertEqual(map[day(10).startOfDay], CalendarPhaseLookup.phase(on: day(10), events: events))
    }

    // MARK: Exclusions

    func testIntimacyIsNotSurfaceable() {
        XCTAssertFalse(InsightFacts.isSurfaceable(raw: "Intimacy:Sex"))
    }

    func testSkinCompositeIsNotSurfaceable() {
        XCTAssertFalse(InsightFacts.isSurfaceable(raw: "Skin:Chin/Acne"))
    }

    func testPatternFinderSkipsSkinRowsKeepsSex() {
        var events: [Event] = []
        for c in 0..<3 {
            let start = cal.date(byAdding: .day, value: -(c * 28) - 28, to: day(28))!
            for d in 1...28 {
                let phase: Event.EventType = d <= 5 ? .menstrual : d <= 13 ? .follicular : d <= 16 ? .ovulation : .luteal
                events.append(Event(eventType: phase, date: cal.date(byAdding: .day, value: d - 1, to: start)!, note: "",
                                    tags: d == 20 ? "Skin:Chin/Acne, Intimacy:Sex" : ""))
            }
        }
        let rows = PatternFinder.heatmap(events: events, archivedBlocks: [], mode: .cycle, today: day(28))
        XCTAssertTrue(rows.contains { $0.tag == "Intimacy:Sex" })
        XCTAssertFalse(rows.contains { $0.tag.hasPrefix("Skin:") })
    }
}
