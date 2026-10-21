import XCTest
@testable import RhythmX

/// Task 18: Quick Log writes through the pure `QuickLogWriter` with the Task 7 rules (Review Focus 3).
@MainActor
final class LogTagIntentTests: XCTestCase {
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: anchor)! }
    private let suiteName = "test.quicklog"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Writer rules

    func testAppendAddsTagToTodaysEvent() {
        var events = [Event(id: "x", eventType: .luteal, date: day(5), note: "")]
        let today = day(5).addingTimeInterval(9 * 3600)

        XCTAssertTrue(QuickLogWriter.append(category: .symptom, value: "Cramps", to: &events, on: today, mode: .cycle))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].tags, "Symptom:Cramps")
        XCTAssertNil(events[0].mode, "logging a tag does not change the event's stored mode")

        XCTAssertTrue(QuickLogWriter.append(category: .mood, value: "Happy", to: &events, on: today, mode: .cycle))
        XCTAssertEqual(events[0].tags, "Symptom:Cramps, Mood:Happy")

        // Planning shares the cycle event on that day.
        XCTAssertTrue(QuickLogWriter.append(category: .planning, value: "Intercourse", to: &events, on: today, mode: .planning))
        XCTAssertEqual(events[0].tags, "Symptom:Cramps, Mood:Happy, Planning:Intercourse")
        XCTAssertEqual(events.count, 1)
    }

    func testRepeatableTagAppendsAgain() {
        var events: [Event] = []
        for _ in 0..<3 {
            XCTAssertTrue(QuickLogWriter.append(category: .menopause, value: "Hot Flashes", to: &events, on: day(7), mode: .menopause))
        }
        XCTAssertEqual(events.count, 1, "all three land on the one carrier")
        XCTAssertEqual(events[0].tags, "Menopause:Hot Flashes, Menopause:Hot Flashes, Menopause:Hot Flashes")
        XCTAssertEqual(TagParser.chips(from: events.map(\.tags)).first?.count, 3)
    }

    func testDuplicateNonRepeatableIsIgnored() {
        var events = [Event(id: "x", eventType: .luteal, date: day(5), note: "", tags: "Symptom:Cramps")]
        let before = events[0].tags
        XCTAssertFalse(QuickLogWriter.append(category: .symptom, value: "Cramps", to: &events, on: day(5), mode: .cycle))
        XCTAssertEqual(events[0].tags, before)
        XCTAssertEqual(events.count, 1)

        // Same rule for a one-per-day menopause tag.
        var carrier = [Event(id: "m", eventType: .follicular, date: day(5), note: "", tags: "Menopause:Poor Sleep", mode: .menopause)]
        XCTAssertFalse(QuickLogWriter.append(category: .menopause, value: "Poor Sleep", to: &carrier, on: day(5), mode: .menopause))
        XCTAssertEqual(carrier[0].tags, "Menopause:Poor Sleep")
        // The legacy Other tag with the same name is still one per day.
        var other = [Event(id: "o", eventType: .luteal, date: day(5), note: "", tags: "Other:Hot Flashes")]
        XCTAssertFalse(QuickLogWriter.append(category: .other, value: "Hot Flashes", to: &other, on: day(5), mode: .cycle))
    }

    func testNoEventForTodayInCycleModeIsNoOp() {
        var events = [Event(id: "y", eventType: .luteal, date: day(4), note: "")]   // yesterday only
        XCTAssertFalse(QuickLogWriter.append(category: .symptom, value: "Cramps", to: &events, on: day(5), mode: .cycle))
        XCTAssertFalse(QuickLogWriter.append(category: .planning, value: "Intercourse", to: &events, on: day(5), mode: .planning))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].tags, "")

        // A menopause carrier on the day is not a home for a cycle tag either.
        var carrierOnly = [Event(id: "m", eventType: .follicular, date: day(5), note: "", mode: .menopause)]
        XCTAssertFalse(QuickLogWriter.append(category: .symptom, value: "Cramps", to: &carrierOnly, on: day(5), mode: .cycle))
        XCTAssertEqual(carrierOnly[0].tags, "")
    }

    func testMenopauseCreatesCarrierEvent() {
        var events = [Event(id: "x", eventType: .ovulation, date: day(5), note: "")]
        XCTAssertTrue(QuickLogWriter.append(category: .menopause, value: "Night Sweats", to: &events, on: day(5), mode: .menopause))
        XCTAssertEqual(events.count, 2, "a menopause tag never lands on a cycle event")
        let carrier = events.last!
        XCTAssertEqual(carrier.mode, .menopause)
        XCTAssertEqual(carrier.eventType, .follicular)
        XCTAssertEqual(carrier.date, day(5))
        XCTAssertEqual(carrier.note, "")
        XCTAssertEqual(carrier.tags, "Menopause:Night Sweats")
        XCTAssertEqual(events[0].tags, "", "the cycle event is untouched")
        XCTAssertTrue(events.filter { $0.effectiveMode != .menopause }.count == 1)
    }

    /// The writer and `EventStore.logTag` are the same rule.
    func testWriterMatchesEventStoreLogTag() {
        let store = EventStore(preview: true)
        store.add(Event(id: "x", eventType: .luteal, date: day(5), note: ""))
        var events = store.events
        let steps: [(TagCategory, String, TrackingMode, Date)] = [
            (.symptom, "Cramps", .cycle, day(5)), (.symptom, "Cramps", .cycle, day(5)),
            (.menopause, "Hot Flashes", .menopause, day(5)), (.menopause, "Hot Flashes", .menopause, day(5)),
            (.menopause, "Brain Fog", .menopause, day(5)), (.menopause, "Brain Fog", .menopause, day(5)),
            (.mood, "Calm", .planning, day(6)), (.mood, "Calm", .cycle, day(5))
        ]
        for (category, value, mode, date) in steps {
            let a = store.logTag("\(category.rawValue):\(value)", on: date, mode: mode)
            let b = QuickLogWriter.append(category: category, value: value, to: &events, on: date, mode: mode)
            XCTAssertEqual(a, b, "\(category.rawValue):\(value) in \(mode)")
        }
        XCTAssertEqual(events.map(\.tags), store.events.map(\.tags))
        XCTAssertEqual(events.map(\.mode), store.events.map(\.mode))
    }

    // MARK: - Shared store round trip (what the intent does)

    func testLogToDefaultsWritesBackAndReportsChange() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        let events = [Event(id: "x", eventType: .luteal, date: day(5), note: "")]
        defaults.set(try JSONEncoder().encode(events), forKey: PersistenceKeys.events)
        defaults.set(TrackingMode.cycle.rawValue, forKey: "trackingMode")

        XCTAssertTrue(QuickLogWriter.log(category: .symptom, value: "Cramps", defaults: defaults, now: day(5)))
        let stored = try JSONDecoder().decode([Event].self, from: defaults.data(forKey: PersistenceKeys.events)!)
        XCTAssertEqual(stored.map(\.tags), ["Symptom:Cramps"])
        XCTAssertEqual(stored.map(\.id), ["x"])

        XCTAssertFalse(QuickLogWriter.log(category: .symptom, value: "Cramps", defaults: defaults, now: day(5)), "duplicate: nothing written")
        XCTAssertFalse(QuickLogWriter.log(category: .symptom, value: "Cramps", defaults: defaults, now: day(9)), "no event today")

        // The mode comes from the shared store.
        defaults.set(TrackingMode.menopause.rawValue, forKey: "trackingMode")
        XCTAssertTrue(QuickLogWriter.log(category: .menopause, value: "Hot Flashes", defaults: defaults, now: day(9)))
        let after = try JSONDecoder().decode([Event].self, from: defaults.data(forKey: PersistenceKeys.events)!)
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after.last?.mode, .menopause)
    }

    // MARK: - Stale chips (a widget still showing the previous mode's chips)

    /// The widget may still show Menopause chips after the app switched to Cycle: such a tap writes nothing.
    func testStaleMenopauseChipInCycleModeIsNoOp() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        let original = try JSONEncoder().encode([Event(id: "x", eventType: .luteal, date: day(5), note: "")])
        defaults.set(original, forKey: PersistenceKeys.events)
        defaults.set(TrackingMode.cycle.rawValue, forKey: "trackingMode")

        XCTAssertFalse(QuickLogWriter.log(category: .menopause, value: "Hot Flashes", defaults: defaults, now: day(5)),
                       "a Hot Flashes chip left over from Menopause writes nothing in Cycle mode")
        XCTAssertEqual(defaults.data(forKey: PersistenceKeys.events), original, "no carrier, no tag")
        XCTAssertFalse(QuickLogWriter.log(category: .mood, value: "Calm", defaults: defaults, now: day(5)),
                       "Mood is a Cycle category, but Calm is a Menopause chip")
        XCTAssertEqual(defaults.data(forKey: PersistenceKeys.events), original)
        // A chip of the stored mode still works.
        XCTAssertTrue(QuickLogWriter.log(category: .symptom, value: "Cramps", defaults: defaults, now: day(5)))
    }

    /// The other way round: a stale Symptom chip in Menopause mode must not create a carrier event.
    func testStaleCycleChipInMenopauseModeCreatesNoCarrier() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(TrackingMode.menopause.rawValue, forKey: "trackingMode")

        XCTAssertFalse(QuickLogWriter.log(category: .symptom, value: "Cramps", defaults: defaults, now: day(5)))
        XCTAssertNil(defaults.data(forKey: PersistenceKeys.events), "no carrier for a stale Symptom chip")
        XCTAssertFalse(QuickLogWriter.log(category: .mood, value: "Happy", defaults: defaults, now: day(5)))
        XCTAssertFalse(QuickLogWriter.log(category: .planning, value: "Intercourse", defaults: defaults, now: day(5)))
        XCTAssertNil(defaults.data(forKey: PersistenceKeys.events))
        // A Menopause chip still creates the carrier.
        XCTAssertTrue(QuickLogWriter.log(category: .menopause, value: "Hot Flashes", defaults: defaults, now: day(5)))
        let stored = try JSONDecoder().decode([Event].self, from: try XCTUnwrap(defaults.data(forKey: PersistenceKeys.events)))
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].mode, .menopause)
        XCTAssertEqual(stored[0].tags, "Menopause:Hot Flashes")
    }

    func testChipAcceptanceFollowsStoredMode() {
        for mode in TrackingMode.allCases {
            for chip in QuickLogChips.chips(for: mode) {
                XCTAssertTrue(QuickLogChips.accepts(category: chip.category, value: chip.value, in: mode), "\(chip.raw) in \(mode)")
                XCTAssertTrue(QuickLogChips.accepts(category: chip.category, value: " \(chip.value) ", in: mode), "value is trimmed")
            }
        }
        XCTAssertFalse(QuickLogChips.accepts(category: .menopause, value: "Hot Flashes", in: .cycle))
        XCTAssertFalse(QuickLogChips.accepts(category: .menopause, value: "Hot Flashes", in: .planning))
        XCTAssertFalse(QuickLogChips.accepts(category: .symptom, value: "Cramps", in: .menopause))
        XCTAssertFalse(QuickLogChips.accepts(category: .planning, value: "Intercourse", in: .cycle))
        XCTAssertFalse(QuickLogChips.accepts(category: .symptom, value: "Headache", in: .cycle), "a Cycle category, but not a chip")
    }

    func testLogToDefaultsLeavesCorruptDataAlone() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(Data("not json".utf8), forKey: PersistenceKeys.events)
        XCTAssertFalse(QuickLogWriter.log(category: .menopause, value: "Hot Flashes", defaults: defaults, now: day(5)))
        XCTAssertEqual(defaults.data(forKey: PersistenceKeys.events), Data("not json".utf8), "never overwrite what cannot be read")
    }

    // MARK: - Chips per mode

    func testChipsPerMode() {
        XCTAssertEqual(QuickLogChips.chips(for: .cycle).map(\.label), ["Cramps", "Tired", "Happy", "Flow"])
        XCTAssertEqual(QuickLogChips.chips(for: .planning).map(\.label), ["Egg White", "Ovulation Test Positive", "Intercourse", "Basal Temp"])
        XCTAssertEqual(QuickLogChips.chips(for: .menopause).map(\.label), ["Hot Flashes", "Night Sweats", "Poor Sleep", "Calm"])
        for mode in TrackingMode.allCases {
            let chips = QuickLogChips.chips(for: mode)
            XCTAssertEqual(chips.count, 4)
            XCTAssertEqual(Set(chips.map(\.raw)).count, 4, "distinct tags in \(mode)")
            for chip in chips {
                XCTAssertEqual(chip.raw, "\(chip.category.rawValue):\(chip.value)")
                XCTAssertTrue(TagLibrary.categories(for: mode).contains(chip.category), "\(chip.raw) is a \(mode) category")
            }
        }
        XCTAssertEqual(QuickLogChips.chips(for: .planning)[3].raw, "Basal Temp:Elevated BBT")
        XCTAssertTrue(QuickLogChips.chips(for: .menopause).prefix(2).allSatisfy { TagLibrary.isRepeatable($0.category, $0.value) })
    }

    func testIntentCarriesCategoryAndValue() {
        let intent = LogTagIntent(category: TagCategory.menopause.rawValue, value: "Hot Flashes")
        XCTAssertEqual(intent.category, "Menopause")
        XCTAssertEqual(intent.value, "Hot Flashes")
        XCTAssertNil(LogTagIntent(category: "Nope", value: "x").tagCategory)
        XCTAssertEqual(intent.tagCategory, .menopause)
    }
}
