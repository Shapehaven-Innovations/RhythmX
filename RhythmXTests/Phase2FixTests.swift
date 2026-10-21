import XCTest
@testable import RhythmX

/// Phase 2 review fixes. Review Focus 2: menopause events never leak into cycle data, and the cycle
/// side never swallows menopause entries. Review Focus 3: repeatable and duplicate tag rules hold
/// while each tag lands on exactly one event.
@MainActor
final class Phase2FixTests: XCTestCase {
    private var archive: ArchivedDataStore!
    private var events: EventStore!

    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20))!
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: today)! }

    override func setUp() {
        super.setUp()
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.archivedData)
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.events)
        archive = ArchivedDataStore()
        events = EventStore(preview: true)
    }

    override func tearDown() {
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.archivedData)
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.events)
        super.tearDown()
    }

    // MARK: - Fixtures

    private var cycleEvents: [Event] { CycleGenerator.events(startDate: day(-40), cycleLength: 28) }

    private var menopauseEvents: [Event] {
        [
            Event(id: "M-OLD", eventType: .follicular, date: day(-30), note: "", tags: "Menopause: Hot Flashes", mode: .menopause),
            Event(id: "M-MID", eventType: .follicular, date: day(-10), note: "", tags: "Menopause: Night Sweats", mode: .menopause),
            Event(id: "M-NEW", eventType: .follicular, date: day(-3), note: "", tags: "Menopause: Hot Flashes", mode: .menopause)
        ]
    }

    private func load(_ list: [Event]) { list.forEach { events.add($0) } }

    private func tags(on date: Date) -> [String] {
        events.events.filter { $0.date.startOfDay == date.startOfDay }.map(\.tags)
    }

    // MARK: - 1. Cycle and Planning archive leave menopause entries live

    func testCycleArchiveMovesOnlyCycleEventsAndLeavesMenopauseEntries() {
        load(cycleEvents)
        load(menopauseEvents)

        let block = archive.archiveCurrent(from: events, mode: .cycle, today: today)

        let archived = block?.groupedEvents.flatMap(\.events) ?? []
        XCTAssertEqual(archived.count, 28)
        XCTAssertTrue(archived.allSatisfy { $0.effectiveMode != .menopause }, "menopause entries never enter a cycle block")
        XCTAssertTrue(events.cycleEvents.isEmpty)
        XCTAssertEqual(Set(events.menopauseEvents.map(\.id)), ["M-OLD", "M-MID", "M-NEW"], "menopause entries stay live")
        XCTAssertEqual(Set(EventStore().events.map(\.id)), ["M-OLD", "M-MID", "M-NEW"], "and the removal is persisted")
    }

    func testPlanningArchiveMovesOnlyCycleEventsAndLeavesMenopauseEntries() {
        load(cycleEvents)
        load(menopauseEvents)

        let block = archive.archiveCurrent(from: events, mode: .planning, today: today)

        XCTAssertEqual(block?.mode, .planning)
        XCTAssertEqual(block?.groupedEvents.flatMap(\.events).count, 28)
        XCTAssertTrue(events.cycleEvents.isEmpty)
        XCTAssertEqual(events.menopauseEvents.count, 3)
    }

    func testCycleArchiveWithOnlyMenopauseEntriesChangesNothing() {
        load(menopauseEvents)

        XCTAssertNil(archive.archiveCurrent(from: events, mode: .cycle, today: today))

        XCTAssertTrue(archive.archivedBlocks.isEmpty)
        XCTAssertEqual(events.events.count, 3)
    }

    // MARK: - 2. Generating a cycle keeps menopause entries

    func testGenerateCycleEventsKeepsMenopauseEntries() {
        events.add(Event(id: "old-cycle", eventType: .luteal, date: day(-20), note: ""))
        events.add(Event(id: "M", eventType: .follicular, date: day(-2), note: "", tags: "Menopause:Hot Flashes", mode: .menopause))

        events.generateCycleEvents(startDate: today, cycleLength: 28)

        XCTAssertEqual(events.cycleEvents.count, 28, "the old cycle is replaced by the generated one")
        XCTAssertFalse(events.events.contains { $0.id == "old-cycle" })
        XCTAssertEqual(events.menopauseEvents.map(\.id), ["M"], "the menopause entry survives generation")
        XCTAssertEqual(events.menopauseEvents.first?.tags, "Menopause:Hot Flashes")
    }

    // MARK: - 3. A tag lands on one event of its own mode

    func testMenopauseTagNeverLandsOnACycleEvent() {
        events.add(Event(id: "x", eventType: .ovulation, date: day(0), note: ""))
        let raw = "Menopause:Hot Flashes"

        XCTAssertTrue(events.logTag(raw, on: day(0), mode: .menopause))
        XCTAssertTrue(events.logTag(raw, on: day(0), mode: .menopause), "repeatable: a second save counts again")

        XCTAssertEqual(events.events.count, 2, "one cycle event plus one menopause carrier")
        let cycle = events.events.first { $0.id == "x" }
        XCTAssertEqual(cycle?.tags, "", "the cycle event is untouched")
        let carrier = events.menopauseEvents.first
        XCTAssertEqual(carrier?.mode, .menopause)
        XCTAssertEqual(TagParser.chips(from: [carrier?.tags ?? ""]).first?.count, 2)
        XCTAssertEqual(TagParser.chips(from: tags(on: day(0))).first?.count, 2, "no double count across the day")
    }

    func testCycleAndPlanningTagsNeverLandOnAMenopauseCarrier() {
        events.add(Event(id: "m", eventType: .follicular, date: day(0), note: "", tags: "Menopause:Brain Fog", mode: .menopause))

        XCTAssertNil(events.eventForLogging(on: day(0), mode: .cycle))
        XCTAssertNil(events.eventForLogging(on: day(0), mode: .planning))
        XCTAssertFalse(events.logTag("Symptom:Cramps", on: day(0), mode: .cycle), "nothing of its own mode to attach to")
        XCTAssertFalse(events.logTag("Planning:Intercourse", on: day(0), mode: .planning))
        XCTAssertEqual(events.events.count, 1, "cycle and planning never invent events")
        XCTAssertEqual(events.events.first?.tags, "Menopause:Brain Fog")

        events.add(Event(id: "x", eventType: .luteal, date: day(0), note: ""))
        XCTAssertEqual(events.eventForLogging(on: day(0), mode: .cycle)?.id, "x")
        XCTAssertEqual(events.eventForLogging(on: day(0), mode: .planning)?.id, "x", "planning shares cycle events")
        XCTAssertTrue(events.logTag("Symptom:Cramps", on: day(0), mode: .cycle))
        XCTAssertEqual(events.events.first { $0.id == "x" }?.tags, "Symptom:Cramps")
        XCTAssertEqual(events.events.first { $0.id == "m" }?.tags, "Menopause:Brain Fog", "the carrier is untouched")
    }

    func testLogTagAppendsToExactlyOneEvent() {
        events.add(Event(id: "a", eventType: .luteal, date: day(0), note: ""))
        events.add(Event(id: "b", eventType: .luteal, date: day(0).addingTimeInterval(3_600), note: ""))

        XCTAssertTrue(events.logTag("Symptom:Cramps", on: day(0), mode: .cycle))

        XCTAssertEqual(tags(on: day(0)).filter { !$0.isEmpty }.count, 1, "the tag is on one event, not every event that day")
        XCTAssertEqual(TagParser.chips(from: tags(on: day(0))).first?.count, 1)
        XCTAssertTrue(events.isDuplicateTag("Symptom:Cramps", on: day(0)), "and a second save is still a duplicate")
    }

    // MARK: - 6. Likely ovulation follows the current cycle

    func testLikelyOvulationAnchorsToTheCurrentCycle() {
        let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        func d(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: anchor)! }
        let two = CycleGenerator.events(startDate: anchor, cycleLength: 28)
            + CycleGenerator.events(startDate: d(28), cycleLength: 28)

        let second = PlanningInsights.make(events: two, overrides: FertileOverrides(), today: d(30))
        XCTAssertEqual(second.likelyOvulation, d(41), "the second cycle's first ovulation day, not the global earliest")
        XCTAssertEqual(second.daysToOvulation, 11)

        let first = PlanningInsights.make(events: two, overrides: FertileOverrides(), today: d(20))
        XCTAssertEqual(first.likelyOvulation, d(13), "before the second cycle starts, the first cycle is current")
        XCTAssertEqual(first.twoWeekWaitDay, 7)

        let early = PlanningInsights.make(events: two, overrides: FertileOverrides(), today: d(-3))
        XCTAssertEqual(early.likelyOvulation, d(13), "before any cycle, the earliest cycle is the one ahead")
    }

    // MARK: - 8. A cold-launch notification tap is kept until the tab view appears

    func testColdLaunchTapIsKeptUntilConsumed() {
        let router = NotificationTapRouter()

        router.remember(userInfo: ["category": "Menopause"])

        let route = router.takePendingRoute()
        XCTAssertEqual(route?.name, .rhythmxOpenTagForm)
        XCTAssertEqual(route?.userInfo["category"], "Menopause")
        XCTAssertNil(router.takePendingRoute(), "consumed once")

        router.remember(userInfo: [:])
        XCTAssertNil(router.takePendingRoute(), "a plain period reminder has no route to keep")
    }
}
