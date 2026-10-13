import XCTest
@testable import RhythmX

@MainActor
final class TagParserTests: XCTestCase {

    func testSplitTrimsAndDropsEmpties() {
        XCTAssertEqual(TagParser.split("Symptom:Cramps,  Mood:Tired ,, "), ["Symptom:Cramps", "Mood:Tired"])
        XCTAssertEqual(TagParser.split(""), [])
        XCTAssertEqual(TagParser.split("Cramps"), ["Cramps"])
    }

    func testLabelStripsCategoryOnlyAtFirstColon() {
        XCTAssertEqual(TagParser.label(for: "Symptom:Cramps"), "Cramps")
        XCTAssertEqual(TagParser.label(for: "Cramps"), "Cramps")
        XCTAssertEqual(TagParser.label(for: "Other: Ratio 2:1"), "Ratio 2:1")
        XCTAssertEqual(TagParser.label(for: " Mood : Tired "), "Tired")
    }

    func testChipsAggregateCountsAndSort() {
        let chips = TagParser.chips(from: [
            "Symptom:Cramps, Mood:Tired",
            "Symptom:Cramps",
            "Cramps",
            ""
        ])
        XCTAssertEqual(chips.map(\.raw), ["Symptom:Cramps", "Cramps", "Mood:Tired"])
        XCTAssertEqual(chips.map(\.count), [2, 1, 1])
        XCTAssertEqual(chips.first?.label, "Cramps")
    }

    func testRemovingTag() {
        XCTAssertEqual(TagParser.removing("Mood:Tired", from: "Symptom:Cramps, Mood:Tired"), "Symptom:Cramps")
        XCTAssertEqual(TagParser.removing("Mood:Tired", from: "Mood:Tired"), "")
        XCTAssertEqual(TagParser.removing("Mood:Tired", from: "Symptom:Cramps,, "), "Symptom:Cramps")
        XCTAssertEqual(TagParser.removing("Nope", from: ""), "")
    }

    func testStoreRemoveTagInPhaseOnly() {
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.events)
        defer { AppGroup.defaults.removeObject(forKey: PersistenceKeys.events) }
        let store = EventStore(preview: true)
        store.add(Event(eventType: .menstrual, date: Date(), note: "", tags: "Symptom:Cramps, Mood:Tired"))
        store.add(Event(eventType: .luteal, date: Date(), note: "", tags: "Mood:Tired"))
        store.removeTag("Mood:Tired", in: .menstrual)
        XCTAssertEqual(store.events.first { $0.eventType == .menstrual }?.tags, "Symptom:Cramps")
        XCTAssertEqual(store.events.first { $0.eventType == .luteal }?.tags, "Mood:Tired")
    }

    func testStoreRemoveTagLeavesNonMatchingEventsUntouched() {
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.events)
        defer { AppGroup.defaults.removeObject(forKey: PersistenceKeys.events) }
        let store = EventStore(preview: true)
        store.add(Event(eventType: .menstrual, date: Date(), note: "", tags: "Mood:Tired"))
        store.add(Event(eventType: .menstrual, date: Date().addingTimeInterval(86400), note: "", tags: "Cramps,, "))
        store.removeTag("Mood:Tired", in: .menstrual)
        XCTAssertTrue(store.events.contains { $0.tags == "Cramps,, " })
        XCTAssertEqual(store.events.filter { $0.tags == "" }.count, 1)
    }
}
