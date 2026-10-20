import XCTest
@testable import RhythmX

@MainActor
final class ArchivedDataStoreTests: XCTestCase {
    private var store: ArchivedDataStore!

    override func setUp() {
        super.setUp()
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.archivedData)
        store = ArchivedDataStore()
    }

    override func tearDown() {
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.archivedData)
        super.tearDown()
    }

    private func block(daysAgo: Int) -> ArchivedDataBlock {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return ArchivedDataBlock(date: date, groupedEvents: [])
    }

    func testDeleteRemovesOnlyThatBlock() {
        let a = block(daysAgo: 60), b = block(daysAgo: 30)
        store.appendArchivedBlock(a)
        store.appendArchivedBlock(b)
        store.deleteArchivedBlock(id: a.id)
        XCTAssertEqual(store.archivedBlocks.map(\.id), [b.id])
    }

    func testDeleteUnknownIdIsNoOp() {
        let a = block(daysAgo: 10)
        store.appendArchivedBlock(a)
        store.deleteArchivedBlock(id: UUID())
        XCTAssertEqual(store.archivedBlocks.count, 1)
    }

    func testDeleteIsPersisted() {
        let a = block(daysAgo: 10)
        store.appendArchivedBlock(a)
        store.deleteArchivedBlock(id: a.id)
        let reloaded = ArchivedDataStore()
        XCTAssertTrue(reloaded.archivedBlocks.isEmpty)
    }

    func testUpdateArchivedEventTagKeepsBlockMode() {
        let event = Event(id: "E-MODE", eventType: .menstrual, date: Date(), note: "", tags: "old")
        let phase = ArchivedDataBlock.PhaseEvents(eventType: .menstrual, events: [event])
        let block = ArchivedDataBlock(date: Date(), groupedEvents: [phase], mode: .planning)
        store.appendArchivedBlock(block)

        store.updateArchivedEventTag(eventId: "E-MODE", newTags: "new")

        let stored = store.archivedBlocks.first { $0.id == block.id }
        XCTAssertEqual(stored?.mode, .planning)
        XCTAssertEqual(stored?.groupedEvents.first?.events.first?.tags, "new")
    }
}
