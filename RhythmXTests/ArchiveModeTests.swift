import XCTest
@testable import RhythmX

/// Task 9: the Archive action works in every mode and Past Cycles can filter, search and delete
/// blocks of any mode. Archiving never retags live events; only the block records the mode.
@MainActor
final class ArchiveModeTests: XCTestCase {
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

    /// A generated 28-day cycle starting 40 days ago, with no stored mode (as 1.9.x and Cycle mode write it).
    private var cycleEvents: [Event] { CycleGenerator.events(startDate: day(-40), cycleLength: 28) }

    private var menopauseEvents: [Event] {
        [
            Event(id: "M-OLD", eventType: .follicular, date: day(-30), note: "", tags: "Menopause: Hot Flashes", mode: .menopause),
            Event(id: "M-MID", eventType: .follicular, date: day(-10), note: "", tags: "Menopause: Night Sweats", mode: .menopause),
            Event(id: "M-NEW", eventType: .follicular, date: day(-3), note: "", tags: "Menopause: Hot Flashes", mode: .menopause)
        ]
    }

    private func load(_ list: [Event]) { list.forEach { events.add($0) } }

    // MARK: - Archive in each mode

    func testArchiveInPlanningModeStoresPlanningBlock() {
        load(cycleEvents)

        let block = archive.archiveCurrent(from: events, mode: .planning, today: today)

        XCTAssertEqual(block?.mode, .planning)
        XCTAssertEqual(block?.effectiveMode, .planning)
        XCTAssertEqual(archive.archivedBlocks.map(\.id), [block?.id])
        XCTAssertTrue(events.events.isEmpty, "Planning archives the whole current cycle, as Cycle does")

        // The block uses the same phase grouping the Archive prompt has always used.
        let phases = block?.groupedEvents ?? []
        XCTAssertEqual(phases.map(\.eventType), Event.EventType.allCases.sorted { $0.rawValue < $1.rawValue })
        XCTAssertEqual(phases.reduce(0) { $0 + $1.events.count }, 28)

        // Only the block carries the mode. The events inside are untouched.
        XCTAssertTrue(phases.flatMap(\.events).allSatisfy { $0.mode == nil }, "archiving never retags events")
    }

    func testArchiveInCycleModeLeavesModeNil() throws {
        load(cycleEvents)

        let block = archive.archiveCurrent(from: events, mode: .cycle, today: today)

        XCTAssertNotNil(block)
        XCTAssertNil(block?.mode, "Cycle blocks keep the 1.9.x shape")
        XCTAssertEqual(block?.effectiveMode, .cycle)
        XCTAssertTrue(events.events.isEmpty)

        // The stored JSON has no mode key, so it is byte-for-byte what 1.9.1 would have written.
        let data = try XCTUnwrap(AppGroup.defaults.data(forKey: PersistenceKeys.archivedData))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(json.count, 1)
        XCTAssertNil(json[0]["mode"])
        XCTAssertNil(ArchivedDataStore().archivedBlocks.first?.mode)
    }

    func testArchiveWithNoEventsChangesNothing() {
        XCTAssertNil(archive.archiveCurrent(from: events, mode: .cycle, today: today))
        XCTAssertNil(archive.archiveCurrent(from: events, mode: .planning, today: today))
        XCTAssertNil(archive.archiveCurrent(from: events, mode: .menopause, today: today))
        XCTAssertTrue(archive.archivedBlocks.isEmpty)
    }

    func testMenopauseArchiveMovesOnlyMenopauseEventsAndLeavesCycleEvents() {
        let cycle = cycleEvents
        load(cycle)
        load(menopauseEvents)

        let block = archive.archiveCurrent(from: events, mode: .menopause, today: today)

        XCTAssertEqual(block?.mode, .menopause)
        XCTAssertEqual(block?.groupedEvents.count, 1, "one group, there are no phases in menopause")
        XCTAssertEqual(block?.groupedEvents.first?.eventType, .follicular)
        XCTAssertEqual(block?.groupedEvents.first?.events.map(\.id), ["M-OLD", "M-MID"], "older than 7 days, oldest first")

        // Cycle events stay. The last week of menopause entries stays too.
        XCTAssertEqual(Set(events.cycleEvents.map(\.id)), Set(cycle.map(\.id)))
        XCTAssertEqual(events.menopauseEvents.map(\.id), ["M-NEW"])
        XCTAssertEqual(events.events.count, cycle.count + 1)

        // The moved events are not in the live store any more, and the removal is persisted.
        XCTAssertEqual(Set(EventStore().events.map(\.id)), Set(events.events.map(\.id)))
    }

    func testMenopauseArchiveWithNothingOlderThanAWeekChangesNothing() {
        load(cycleEvents)
        events.add(Event(id: "M-NEW", eventType: .follicular, date: day(-3), note: "", tags: "Menopause: Hot Flashes", mode: .menopause))
        let before = events.events.map(\.id)

        XCTAssertNil(archive.archiveCurrent(from: events, mode: .menopause, today: today))

        XCTAssertTrue(archive.archivedBlocks.isEmpty)
        XCTAssertEqual(events.events.map(\.id), before)
    }

    // MARK: - Past Cycles filter, search and delete

    func testFilterReturnsOnlyMatchingModes() {
        load(cycleEvents)
        let cycleBlock = archive.archiveCurrent(from: events, mode: .cycle, today: today)!
        load(CycleGenerator.events(startDate: day(-10), cycleLength: 30))
        let planningBlock = archive.archiveCurrent(from: events, mode: .planning, today: today)!
        load(menopauseEvents)
        let menopauseBlock = archive.archiveCurrent(from: events, mode: .menopause, today: today)!

        XCTAssertEqual(Set(archive.blocks(matching: nil).map(\.id)), [cycleBlock.id, planningBlock.id, menopauseBlock.id])
        XCTAssertEqual(archive.blocks(matching: .cycle).map(\.id), [cycleBlock.id])
        XCTAssertEqual(archive.blocks(matching: .planning).map(\.id), [planningBlock.id])
        XCTAssertEqual(archive.blocks(matching: .menopause).map(\.id), [menopauseBlock.id])

        // The search variant with empty text is the same as the plain filter.
        XCTAssertEqual(archive.blocks(matching: .planning, search: "").map(\.id), [planningBlock.id])
        XCTAssertEqual(archive.blocks(matching: nil, search: "  ").count, 3)
    }

    func testDeleteAndSearchWorkForMenopauseBlocks() {
        load(cycleEvents)
        archive.archiveCurrent(from: events, mode: .cycle, today: today)
        load(menopauseEvents)
        let menopauseBlock = archive.archiveCurrent(from: events, mode: .menopause, today: today)!

        // Search narrows the block to the matching events and keeps its mode.
        let hits = archive.blocks(matching: .menopause, search: "hot")
        XCTAssertEqual(hits.map(\.id), [menopauseBlock.id])
        XCTAssertEqual(hits.first?.mode, .menopause, "a searched block keeps its mode label")
        XCTAssertEqual(hits.first?.groupedEvents.flatMap(\.events).map(\.id), ["M-OLD"])

        XCTAssertEqual(archive.blocks(matching: .menopause, search: "sweats").first?.groupedEvents.flatMap(\.events).map(\.id), ["M-MID"])
        XCTAssertTrue(archive.blocks(matching: .menopause, search: "cramps").isEmpty)
        XCTAssertEqual(archive.blocks(matching: nil, search: "hot").map(\.id), [menopauseBlock.id],
                       "All plus search reaches menopause blocks too")

        // Tag editing and delete work on the block like on any other.
        archive.updateArchivedEventTag(eventId: "M-MID", newTags: "Menopause: Poor Sleep")
        XCTAssertEqual(archive.blocks(matching: .menopause, search: "poor sleep").first?.mode, .menopause)

        archive.deleteArchivedBlock(id: menopauseBlock.id)
        XCTAssertTrue(archive.blocks(matching: .menopause).isEmpty)
        XCTAssertEqual(archive.archivedBlocks.count, 1, "the cycle block is untouched")
        XCTAssertEqual(ArchivedDataStore().archivedBlocks.count, 1, "the delete is persisted")
    }
}
