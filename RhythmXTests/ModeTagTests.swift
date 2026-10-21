import XCTest
@testable import RhythmX

/// Task 7: mode tag categories and repeatable tags.
/// Review Focus 3: a repeatable tag ("Hot Flashes") logged several times in one day counts each time,
/// while a normal tag is still blocked as a duplicate.
@MainActor
final class ModeTagTests: XCTestCase {
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: anchor)! }

    private func tags(in store: EventStore, on date: Date) -> [String] {
        store.events.filter { $0.date.startOfDay == date.startOfDay }.map(\.tags)
    }

    // MARK: - Categories

    func testRawValuesAreStable() {
        XCTAssertEqual(TagCategory.planning.rawValue, "Planning")
        XCTAssertEqual(TagCategory.menopause.rawValue, "Menopause")
        XCTAssertTrue(TagCategory.allCases.contains(.planning))
        XCTAssertTrue(TagCategory.allCases.contains(.menopause))
    }

    func testTagCategoryIsCodable() throws {
        let data = try JSONEncoder().encode([TagCategory.planning, .menopause, .cervicalMucus])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"Planning\",\"Menopause\",\"Cervical Mucus\"]")
        let decoded = try JSONDecoder().decode([TagCategory].self, from: data)
        XCTAssertEqual(decoded, [.planning, .menopause, .cervicalMucus])
    }

    func testCategoriesPerMode() {
        XCTAssertEqual(TagLibrary.categories(for: .cycle),
                       [.symptom, .mood, .dietary, .exercise, .medication, .cervicalMucus, .basalTemp, .other])
        XCTAssertEqual(TagLibrary.categories(for: .planning),
                       [.planning, .cervicalMucus, .basalTemp, .mood, .symptom, .medication, .other])
        XCTAssertEqual(TagLibrary.categories(for: .menopause),
                       [.menopause, .mood, .symptom, .medication, .other])
    }

    func testLibraryTagsForModeCategories() {
        XCTAssertEqual(TagLibrary.tags[.planning],
                       ["Ovulation Test Negative", "Ovulation Test Faint", "Ovulation Test Positive",
                        "Ovulation Test Peak", "Intercourse", "Fertility Supplement"])
        XCTAssertEqual(TagLibrary.tags[.menopause],
                       ["Hot Flashes", "Night Sweats", "Poor Sleep", "Brain Fog", "Joint Pain",
                        "Vaginal Dryness", "Low Libido", "Heart Palpitations"])
        // Existing categories are unchanged, so stored tags keep their meaning.
        XCTAssertEqual(TagLibrary.tags[.other],
                       ["Poor Sleep", "Acne", "Water Retention", "Hot Flashes", "Night Sweats", "Mild Cramping"])
    }

    // MARK: - Repeatable tags

    func testOnlyMenopauseHotFlashesAndNightSweatsAreRepeatable() {
        XCTAssertTrue(TagLibrary.isRepeatable(.menopause, "Hot Flashes"))
        XCTAssertTrue(TagLibrary.isRepeatable(.menopause, "Night Sweats"))
        XCTAssertFalse(TagLibrary.isRepeatable(.menopause, "Poor Sleep"))
        XCTAssertFalse(TagLibrary.isRepeatable(.other, "Hot Flashes"), "the legacy Other tag stays a one-per-day tag")
        XCTAssertFalse(TagLibrary.isRepeatable(.symptom, "Cramps"))

        XCTAssertTrue(TagLibrary.isRepeatable(raw: "Menopause:Hot Flashes"))
        XCTAssertTrue(TagLibrary.isRepeatable(raw: "Menopause: Night Sweats"))
        XCTAssertFalse(TagLibrary.isRepeatable(raw: "Other:Hot Flashes"))
        XCTAssertFalse(TagLibrary.isRepeatable(raw: "Hot Flashes"))
    }

    /// Review Focus 3.
    func testRepeatableTagLoggedThreeTimesCountsThree() {
        let store = EventStore(preview: true)
        let raw = "Menopause:Hot Flashes"

        for _ in 0..<3 {
            XCTAssertFalse(store.isDuplicateTag(raw, on: day(5)), "a repeatable tag is never a duplicate")
            XCTAssertTrue(store.logTag(raw, on: day(5), mode: .menopause))
        }

        let chips = TagParser.chips(from: tags(in: store, on: day(5)))
        XCTAssertEqual(chips.count, 1)
        XCTAssertEqual(chips.first?.raw, raw)
        XCTAssertEqual(chips.first?.count, 3)
        XCTAssertEqual(store.events.count, 1, "all three saves land on the one carrier event")
    }

    /// Review Focus 3.
    func testNonRepeatableTagStillBlockedAsDuplicate() {
        let store = EventStore(preview: true)
        store.add(Event(id: "c", eventType: .luteal, date: day(20), note: ""))
        let raw = "Symptom:Cramps"

        XCTAssertFalse(store.isDuplicateTag(raw, on: day(20)))
        XCTAssertTrue(store.logTag(raw, on: day(20), mode: .cycle))

        XCTAssertTrue(store.isDuplicateTag(raw, on: day(20)))
        XCTAssertFalse(store.logTag(raw, on: day(20), mode: .cycle), "a second save is refused")

        let chips = TagParser.chips(from: tags(in: store, on: day(20)))
        XCTAssertEqual(chips.map(\.raw), [raw])
        XCTAssertEqual(chips.first?.count, 1)

        // The same rule holds in menopause mode for a non-repeatable menopause tag.
        XCTAssertTrue(store.logTag("Menopause:Brain Fog", on: day(21), mode: .menopause))
        XCTAssertTrue(store.isDuplicateTag("Menopause:Brain Fog", on: day(21)))
        XCTAssertFalse(store.logTag("Menopause:Brain Fog", on: day(21), mode: .menopause))
        XCTAssertEqual(TagParser.chips(from: tags(in: store, on: day(21))).first?.count, 1)
    }

    func testDuplicateCheckIsPerDay() {
        let store = EventStore(preview: true)
        store.add(Event(id: "a", eventType: .luteal, date: day(1), note: "", tags: "Symptom:Cramps"))
        store.add(Event(id: "b", eventType: .luteal, date: day(2), note: ""))

        XCTAssertTrue(store.isDuplicateTag("Symptom:Cramps", on: day(1)))
        XCTAssertFalse(store.isDuplicateTag("Symptom:Cramps", on: day(2)))
    }

    // MARK: - Carrier events

    func testMenopauseLoggingCreatesCarrierEventWithMenopauseMode() {
        let store = EventStore(preview: true)
        XCTAssertTrue(store.events.isEmpty)

        let carrier = store.eventForLogging(on: day(10), mode: .menopause)

        XCTAssertNotNil(carrier)
        XCTAssertEqual(carrier?.mode, .menopause)
        XCTAssertEqual(carrier?.eventType, .follicular)
        XCTAssertEqual(carrier?.date, day(10))
        XCTAssertEqual(carrier?.note, "")
        XCTAssertEqual(store.events.map(\.id), [carrier?.id], "the carrier is stored")
        XCTAssertTrue(store.cycleEvents.isEmpty, "a carrier never counts as cycle data")
        XCTAssertEqual(store.menopauseEvents.map(\.id), [carrier?.id])

        // Asking again on the same day reuses the carrier instead of adding a second one.
        XCTAssertEqual(store.eventForLogging(on: day(10), mode: .menopause)?.id, carrier?.id)
        XCTAssertEqual(store.events.count, 1)
    }

    func testCycleLoggingWithNoEventDoesNotCreateOne() {
        let store = EventStore(preview: true)

        XCTAssertNil(store.eventForLogging(on: day(10), mode: .cycle))
        XCTAssertNil(store.eventForLogging(on: day(10), mode: .planning))
        XCTAssertTrue(store.events.isEmpty)

        XCTAssertFalse(store.logTag("Symptom:Cramps", on: day(10), mode: .cycle), "nothing to attach the tag to")
        XCTAssertFalse(store.logTag("Planning:Intercourse", on: day(10), mode: .planning))
        XCTAssertTrue(store.events.isEmpty, "existing behavior: cycle and planning never invent events")
    }

    func testLoggingUsesTheExistingEventOnThatDay() {
        let store = EventStore(preview: true)
        let existing = Event(id: "x", eventType: .ovulation, date: day(14), note: "")
        store.add(existing)

        XCTAssertEqual(store.eventForLogging(on: day(14), mode: .cycle)?.id, "x")
        XCTAssertEqual(store.eventForLogging(on: day(14), mode: .planning)?.id, "x")
        XCTAssertEqual(store.events.count, 1)

        // Menopause never shares a cycle event: it gets a carrier of its own on that day.
        let carrier = store.eventForLogging(on: day(14), mode: .menopause)
        XCTAssertNotEqual(carrier?.id, "x")
        XCTAssertEqual(carrier?.mode, .menopause)
        XCTAssertEqual(store.events.count, 2)

        XCTAssertTrue(store.logTag("Planning:Intercourse", on: day(14), mode: .planning))
        let cycleEvent = store.events.first { $0.id == "x" }
        XCTAssertEqual(cycleEvent?.tags, "Planning:Intercourse")
        XCTAssertNil(cycleEvent?.mode, "logging a tag does not change the event's stored mode")
        XCTAssertEqual(store.events.first { $0.id == carrier?.id }?.tags, "", "the carrier is untouched")
    }
}
