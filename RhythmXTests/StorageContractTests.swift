import XCTest
@testable import RhythmX

final class StorageContractTests: XCTestCase {
    func testPersistenceKeysUnchanged() {
        XCTAssertEqual(PersistenceKeys.events, "com.example.rhythm(x).events")
        XCTAssertEqual(PersistenceKeys.archivedData, "com.example.rhythm(x).archivedData")
    }

    private let eventJSON = #"{"id":"E1","eventType":"menstrual","date":780000000.5,"note":"n","tags":"Mood:Tired, Cramps"}"#

    func testDecodesLegacyEvents() throws {
        let data = Data("[\(eventJSON)]".utf8)
        let events = try JSONDecoder().decode([Event].self, from: data)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].id, "E1")
        XCTAssertEqual(events[0].eventType, .menstrual)
        XCTAssertEqual(events[0].date.timeIntervalSinceReferenceDate, 780000000.5, accuracy: 0.001)
        XCTAssertEqual(events[0].note, "n")
        XCTAssertEqual(events[0].tags, "Mood:Tired, Cramps")
    }

    func testDecodesLegacyArchivedBlocks() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":780100000,"groupedEvents":[{"eventType":"menstrual","events":[\#(eventJSON)]}]}]"#
        let blocks = try JSONDecoder().decode([ArchivedDataBlock].self, from: Data(json.utf8))
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].id, UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        XCTAssertEqual(blocks[0].date.timeIntervalSinceReferenceDate, 780100000, accuracy: 0.001)
        XCTAssertEqual(blocks[0].groupedEvents.count, 1)
        XCTAssertEqual(blocks[0].groupedEvents[0].eventType, .menstrual)
        XCTAssertEqual(blocks[0].groupedEvents[0].events[0].tags, "Mood:Tired, Cramps")
    }

    func testEventRoundTrip() throws {
        let e = Event(id: "X", eventType: .luteal, date: Date(timeIntervalSinceReferenceDate: 123456), note: "a", tags: "b,c")
        let back = try JSONDecoder().decode(Event.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(back.id, e.id)
        XCTAssertEqual(back.eventType, e.eventType)
        XCTAssertEqual(back.date, e.date)
        XCTAssertEqual(back.note, e.note)
        XCTAssertEqual(back.tags, e.tags)
    }
}
