import XCTest
@testable import RhythmX

/// Review Focus 2: menopause events and blocks must never leak into cycle statistics,
/// prediction, the phase ring, the fertile window or the widget snapshot.
@MainActor
final class ModeFilterTests: XCTestCase {
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: anchor)! }

    private let modeKeys = ["trackingMode", "defaultModeOnLaunch"]

    override func setUp() {
        super.setUp()
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.archivedData)
        modeKeys.forEach { AppGroup.defaults.removeObject(forKey: $0) }
    }

    override func tearDown() {
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.archivedData)
        modeKeys.forEach { AppGroup.defaults.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - Fixtures

    private var cycleEvents: [Event] { CycleGenerator.events(startDate: anchor, cycleLength: 28) }

    /// Menopause entries logged well after the current cycle. Without filtering they would stretch the
    /// cycle span, move the next period estimate and widen the fertile window.
    private var menopauseEvents: [Event] {
        [
            Event(id: "M-1", eventType: .menstrual, date: day(40), note: "Spotting", tags: "Symptom: Spotting", mode: .menopause),
            Event(id: "M-2", eventType: .ovulation, date: day(45), note: "", tags: "Menopause: Hot Flashes", mode: .menopause),
            Event(id: "M-3", eventType: .luteal, date: day(50), note: "", tags: "Menopause: Night Sweats", mode: .menopause)
        ]
    }

    private func block(startingAt start: Date, cycleLength: Int, mode: TrackingMode? = nil) -> ArchivedDataBlock {
        let events = CycleGenerator.events(startDate: start, cycleLength: cycleLength)
        let grouped = Dictionary(grouping: events, by: { $0.eventType })
            .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) }
        return ArchivedDataBlock(date: start, groupedEvents: grouped, mode: mode)
    }

    // MARK: - EventStore

    func testMenopauseEventsExcludedFromCycleEvents() {
        let store = EventStore(preview: true)
        let legacy = Event(id: "legacy", eventType: .menstrual, date: day(0), note: "")
        let cycle = Event(id: "cycle", eventType: .follicular, date: day(6), note: "", mode: .cycle)
        let planning = Event(id: "planning", eventType: .ovulation, date: day(13), note: "", mode: .planning)
        let menopause = Event(id: "menopause", eventType: .menstrual, date: day(40), note: "", mode: .menopause)
        [legacy, cycle, planning, menopause].forEach { store.add($0) }

        XCTAssertEqual(store.cycleEvents.map(\.id), ["legacy", "cycle", "planning"])
        XCTAssertEqual(store.menopauseEvents.map(\.id), ["menopause"])
        XCTAssertEqual(store.events.count, 4, "the filters are views, the store keeps everything")
    }

    // MARK: - ArchivedDataStore

    func testArchivedBlocksFilterByMode() {
        let store = ArchivedDataStore()
        let legacy = block(startingAt: day(-120), cycleLength: 28)
        let planning = block(startingAt: day(-90), cycleLength: 30, mode: .planning)
        let menopause = block(startingAt: day(-60), cycleLength: 28, mode: .menopause)
        store.replaceAll([legacy, planning, menopause])

        XCTAssertEqual(Set(store.blocks(matching: nil).map(\.id)), [legacy.id, planning.id, menopause.id])
        XCTAssertEqual(store.blocks(matching: .cycle).map(\.id), [legacy.id])
        XCTAssertEqual(store.blocks(matching: .planning).map(\.id), [planning.id])
        XCTAssertEqual(store.blocks(matching: .menopause).map(\.id), [menopause.id])
        XCTAssertEqual(Set(store.cycleBlocks.map(\.id)), [legacy.id, planning.id])
    }

    // MARK: - Prediction

    func testPredictionIgnoresMenopauseBlocks() {
        let cycleBlock = block(startingAt: anchor, cycleLength: 28)
        let baseline = CyclePredictionService.predictedStartDate(from: [cycleBlock])
        XCTAssertEqual(baseline, day(28))

        // A later menopause block with a very different span must not move the estimate.
        let later = block(startingAt: day(60), cycleLength: 90, mode: .menopause)
        XCTAssertEqual(CyclePredictionService.predictedStartDate(from: [cycleBlock, later]), baseline)
        XCTAssertNil(CyclePredictionService.predictedStartDate(from: [later]),
                     "menopause blocks alone give no period prediction")
    }

    func testPredictionIgnoresTinyArchivedBlocks() {
        // A block under 15 days (a period start logged by mistake and then logged again) must not drag the
        // average down.
        let cycleBlock = block(startingAt: anchor, cycleLength: 28)
        let tinyEvents = (28..<31).map { Event(eventType: .menstrual, date: day($0), note: "") }
        let tiny = ArchivedDataBlock(date: day(31), groupedEvents: [.init(eventType: .menstrual, events: tinyEvents)])
        XCTAssertEqual(CyclePredictionService.predictedStartDate(from: [cycleBlock, tiny]), day(28 + 28),
                       "only the 28 day cycle is averaged; the estimate counts from the latest start")
        XCTAssertNil(CyclePredictionService.predictedStartDate(from: [tiny]), "a tiny block alone predicts nothing")

        let stats = InsightsViewModel(events: [], archivedBlocks: [cycleBlock, tiny], appSettings: AppSettings())
            .cycleStats(today: day(40))
        XCTAssertEqual(stats.averageCycleLength, 28)
    }

    // MARK: - Widget snapshot

    func testWidgetSnapshotIgnoresMenopauseEvents() {
        let cycleBlock = block(startingAt: day(-60), cycleLength: 30)
        let menopauseBlock = block(startingAt: day(60), cycleLength: 90, mode: .menopause)

        let cycleOnly = PhaseWidgetSnapshot.make(events: cycleEvents, archived: [cycleBlock], today: day(13))
        let mixed = PhaseWidgetSnapshot.make(events: cycleEvents + menopauseEvents,
                                             archived: [cycleBlock, menopauseBlock], today: day(13))

        XCTAssertEqual(mixed, cycleOnly)
        XCTAssertEqual(mixed.daysUntilNext, 15)
        XCTAssertEqual(mixed.cycleLength, 28)
        XCTAssertEqual(mixed.averageCycleLength, 30)
    }

    func testWidgetLoadFromDefaultsIgnoresMenopauseEvents() {
        let suite = "test.modefilter.widget"
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        let d = UserDefaults(suiteName: suite)!
        d.set(try! JSONEncoder().encode(cycleEvents + menopauseEvents), forKey: PersistenceKeys.events)
        d.set(try! JSONEncoder().encode([block(startingAt: day(60), cycleLength: 90, mode: .menopause)]),
              forKey: PersistenceKeys.archivedData)

        let loaded = PhaseWidgetSnapshot.load(defaults: d, today: day(13))

        XCTAssertEqual(loaded, PhaseWidgetSnapshot.make(events: cycleEvents, archived: [], today: day(13)))
    }

    // MARK: - Fertile window

    func testFertileWindowIgnoresMenopauseEvents() {
        let expected = FertileWindow.days(events: cycleEvents, overrides: FertileOverrides())
        XCTAssertFalse(expected.isEmpty)

        let mixed = FertileWindow.days(events: cycleEvents + menopauseEvents, overrides: FertileOverrides())
        XCTAssertEqual(mixed, expected)
        XCTAssertFalse(mixed.contains(FertileWindow.dayKey(day(45))), "a menopause ovulation entry never opens a window")
        XCTAssertTrue(FertileWindow.days(events: menopauseEvents, overrides: FertileOverrides()).isEmpty)

        let suite = "test.modefilter.fertile"
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        let store = FertileStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(store.days(events: cycleEvents + menopauseEvents), expected)
        XCTAssertFalse(store.isFertile(day(45), events: cycleEvents + menopauseEvents))
    }

    // MARK: - Launch mode

    func testTrackingModeDefaultsToCycleAndRoundTrips() {
        let settings = AppSettings()
        XCTAssertEqual(settings.trackingMode, .cycle)
        XCTAssertEqual(settings.trackingModeRaw, "cycle")
        XCTAssertEqual(settings.defaultModeOnLaunch, "last")

        settings.trackingMode = .planning
        XCTAssertEqual(settings.trackingModeRaw, "planning")
        XCTAssertEqual(AppSettings().trackingMode, .planning, "the mode is remembered")

        settings.trackingModeRaw = "not a mode"
        XCTAssertEqual(settings.trackingMode, .cycle, "an unknown stored value falls back to Cycle")
    }

    func testLaunchModeLastKeepsStoredMode() {
        let settings = AppSettings()
        settings.trackingMode = .menopause
        settings.defaultModeOnLaunch = "last"

        settings.applyLaunchMode()

        XCTAssertEqual(settings.trackingMode, .menopause)
    }

    func testLaunchModeFixedOverrides() {
        let settings = AppSettings()
        settings.trackingMode = .menopause
        settings.defaultModeOnLaunch = "planning"

        settings.applyLaunchMode()

        XCTAssertEqual(settings.trackingMode, .planning)
        XCTAssertEqual(settings.defaultModeOnLaunch, "planning", "the launch preference itself is unchanged")

        settings.defaultModeOnLaunch = "not a mode"
        settings.applyLaunchMode()
        XCTAssertEqual(settings.trackingMode, .planning, "an unknown launch value changes nothing")
    }
}
