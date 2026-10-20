import XCTest
@testable import RhythmX

@MainActor
final class EventStoreTests: XCTestCase {

    var store: EventStore!

    override func setUp() {
        super.setUp()
        store = EventStore(preview: true)
    }

    // MARK: - Writes made by the Quick Log widget between this store's reads and writes

    private let day5 = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 5))!

    /// Clears the shared keys these tests touch and restores whatever was there afterwards.
    private func useSharedStore(mode: TrackingMode) {
        let events = AppGroup.defaults.data(forKey: PersistenceKeys.events)
        let storedMode = AppGroup.defaults.string(forKey: "trackingMode")
        addTeardownBlock {
            AppGroup.defaults.set(events, forKey: PersistenceKeys.events)
            AppGroup.defaults.set(storedMode, forKey: "trackingMode")
        }
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.events)
        AppGroup.defaults.set(mode.rawValue, forKey: "trackingMode")
    }

    private func storedEvents() throws -> [Event] {
        try JSONDecoder().decode([Event].self, from: try XCTUnwrap(AppGroup.defaults.data(forKey: PersistenceKeys.events)))
    }

    /// The widget logs a tag while the app is not active; the app's next save must not overwrite it.
    func testSaveKeepsTagWrittenByWidgetWhileAppWasAway() throws {
        useSharedStore(mode: .cycle)
        let live = EventStore(preview: false)
        live.add(Event(id: "x", eventType: .luteal, date: day5, note: ""))

        XCTAssertTrue(QuickLogWriter.log(category: .symptom, value: "Cramps", defaults: AppGroup.defaults, now: day5))
        XCTAssertEqual(live.events[0].tags, "", "the app has not reloaded since the widget wrote")

        live.add(Event(id: "y", eventType: .follicular, date: day5.addingTimeInterval(86_400), note: ""))

        let stored = try storedEvents()
        XCTAssertEqual(stored.map(\.id), ["x", "y"])
        XCTAssertEqual(stored[0].tags, "Symptom:Cramps", "the widget's tag survives the app-side save")
        XCTAssertEqual(live.events.first { $0.id == "x" }?.tags, "Symptom:Cramps", "and is in memory too")
    }

    /// A carrier the widget created is kept; an event the app deleted meanwhile stays deleted.
    func testSaveKeepsWidgetCarrierButNotEventsTheAppDeleted() throws {
        useSharedStore(mode: .menopause)
        let live = EventStore(preview: false)
        live.add(Event(id: "x", eventType: .luteal, date: day5, note: ""))
        live.add(Event(id: "gone", eventType: .ovulation, date: day5.addingTimeInterval(86_400), note: ""))

        XCTAssertTrue(QuickLogWriter.log(category: .menopause, value: "Hot Flashes", defaults: AppGroup.defaults, now: day5))
        XCTAssertEqual(try storedEvents().count, 3)

        live.delete(try XCTUnwrap(live.events.first { $0.id == "gone" }))

        let stored = try storedEvents()
        XCTAssertEqual(stored.count, 2)
        XCTAssertFalse(stored.contains { $0.id == "gone" }, "the app's delete stands")
        let carrier = try XCTUnwrap(stored.first { $0.mode == .menopause })
        XCTAssertEqual(carrier.tags, "Menopause:Hot Flashes")
        XCTAssertEqual(live.events.map(\.id).sorted(), stored.map(\.id).sorted())
    }

    /// Widget and app each make a Menopause carrier for the same day: the tags end up on one carrier.
    func testSaveUnionsWidgetCarrierIntoTheAppsCarrierForTheSameDay() throws {
        useSharedStore(mode: .menopause)
        let live = EventStore(preview: false)

        XCTAssertTrue(QuickLogWriter.log(category: .menopause, value: "Hot Flashes", defaults: AppGroup.defaults, now: day5))
        XCTAssertTrue(live.logTag("Menopause:Poor Sleep", on: day5, mode: .menopause))

        let stored = try storedEvents()
        XCTAssertEqual(stored.count, 1, "one carrier for the day, not two")
        XCTAssertEqual(Set(TagParser.split(stored[0].tags)), ["Menopause:Hot Flashes", "Menopause:Poor Sleep"])
        XCTAssertEqual(live.events.count, 1)
        XCTAssertEqual(live.events[0].tags, stored[0].tags)
    }

    func testAddEventAppendsToEvents() {
        let event = Event(eventType: .menstrual, date: Date(), note: "test")
        store.add(event)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events.first?.id, event.id)
    }

    func testDeleteEventRemovesFromEvents() {
        let event = Event(eventType: .follicular, date: Date(), note: "test")
        store.add(event)
        store.delete(event)
        XCTAssertTrue(store.events.isEmpty)
    }

    func testUpdateEventReplacesById() {
        let original = Event(eventType: .luteal, date: Date(), note: "original")
        store.add(original)
        var updated = original
        updated.note = "updated"
        store.update(updated)
        XCTAssertEqual(store.events.first?.note, "updated")
    }

    func testGenerateCycleEventsProducesCorrectCount() {
        store.generateCycleEvents(startDate: Date(), cycleLength: 28)
        XCTAssertEqual(store.events.count, 28)
    }

    func testGenerateCycleEventsCoversFourPhases() {
        store.generateCycleEvents(startDate: Date(), cycleLength: 28)
        let types = Set(store.events.map { $0.eventType })
        XCTAssertEqual(types, [.menstrual, .follicular, .ovulation, .luteal])
    }

    // Onboarding's "Start tracking" must not wipe events a restore brought in.
    func testInitialGenerationSkipsWhenEventsExist() {
        let restored = Event(id: "restored", eventType: .menstrual, date: Date(), note: "from backup")
        store.add(restored)

        let generated = store.generateInitialCycleEventsIfEmpty(startDate: Date(), cycleLength: 28)

        XCTAssertFalse(generated)
        XCTAssertEqual(store.events.map(\.id), ["restored"])
    }

    func testInitialGenerationRunsWhenEmpty() {
        XCTAssertTrue(store.generateInitialCycleEventsIfEmpty(startDate: Date(), cycleLength: 28))
        XCTAssertEqual(store.events.count, 28)
    }

    func testClearAllEventsEmptiesStore() {
        store.generateCycleEvents(startDate: Date(), cycleLength: 28)
        store.clearAllEvents()
        XCTAssertTrue(store.events.isEmpty)
    }

    func testPreviewModeDoesNotPersist() {
        let event = Event(eventType: .ovulation, date: Date(), note: "preview")
        store.add(event)
        let freshStore = EventStore(preview: true)
        XCTAssertTrue(freshStore.events.isEmpty)
    }
}
