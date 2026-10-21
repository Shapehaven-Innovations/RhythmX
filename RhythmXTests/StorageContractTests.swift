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

    func testLegacyEventJSONDecodesWithNilMode() throws {
        let event = try JSONDecoder().decode(Event.self, from: Data(eventJSON.utf8))
        XCTAssertNil(event.mode)
        XCTAssertEqual(event.effectiveMode, .cycle)
    }

    func testLegacyBlockJSONDecodesWithNilMode() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":780100000,"groupedEvents":[{"eventType":"menstrual","events":[\#(eventJSON)]}]}"#
        let block = try JSONDecoder().decode(ArchivedDataBlock.self, from: Data(json.utf8))
        XCTAssertNil(block.mode)
        XCTAssertEqual(block.effectiveMode, .cycle)
    }

    func testUnknownModeDecodesAsNilWithoutFailingTheArray() throws {
        let unknown = #"{"id":"P1","eventType":"luteal","date":780000000,"note":"later","tags":"Mood:Calm","mode":"perimenopause"}"#
        let events = try JSONDecoder().decode([Event].self, from: Data("[\(eventJSON),\(unknown)]".utf8))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].id, "E1")
        XCTAssertNil(events[1].mode)
        XCTAssertEqual(events[1].id, "P1")
        XCTAssertEqual(events[1].eventType, .luteal)
        XCTAssertEqual(events[1].date.timeIntervalSinceReferenceDate, 780000000, accuracy: 0.001)
        XCTAssertEqual(events[1].note, "later")
        XCTAssertEqual(events[1].tags, "Mood:Calm")

        let blockJSON = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":780100000,"mode":"perimenopause","groupedEvents":[{"eventType":"luteal","events":[\#(unknown)]}]},{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","date":780200000,"mode":"menopause","groupedEvents":[]}]"#
        let blocks = try JSONDecoder().decode([ArchivedDataBlock].self, from: Data(blockJSON.utf8))
        XCTAssertEqual(blocks.count, 2)
        XCTAssertNil(blocks[0].mode)
        XCTAssertEqual(blocks[0].id, UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        XCTAssertEqual(blocks[0].date.timeIntervalSinceReferenceDate, 780100000, accuracy: 0.001)
        XCTAssertEqual(blocks[0].groupedEvents[0].events[0].id, "P1")
        XCTAssertNil(blocks[0].groupedEvents[0].events[0].mode)
        XCTAssertEqual(blocks[1].mode, .menopause, "known modes still decode")
    }

    func testBlockModeEncodingUnchanged() throws {
        let plain = ArchivedDataBlock(date: Date(timeIntervalSinceReferenceDate: 1), groupedEvents: [])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(plain), as: UTF8.self).contains("\"mode\""))
        let planning = ArchivedDataBlock(date: Date(timeIntervalSinceReferenceDate: 1), groupedEvents: [], mode: .planning)
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(planning), as: UTF8.self).contains("\"mode\":\"planning\""))
        let back = try JSONDecoder().decode(ArchivedDataBlock.self, from: JSONEncoder().encode(planning))
        XCTAssertEqual(back.mode, .planning)
    }

    func testModeRoundTrips() throws {
        let withMode = Event(id: "M", eventType: .menstrual, date: Date(timeIntervalSinceReferenceDate: 1), note: "", tags: "", mode: .menopause)
        let back = try JSONDecoder().decode(Event.self, from: JSONEncoder().encode(withMode))
        XCTAssertEqual(back.mode, .menopause)
        XCTAssertEqual(back.effectiveMode, .menopause)

        let withoutMode = Event(id: "N", eventType: .menstrual, date: Date(timeIntervalSinceReferenceDate: 1), note: "", tags: "")
        let encoded = try JSONEncoder().encode(withoutMode)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(json.contains("\"mode\""))
    }
}
