import XCTest
@testable import RhythmX

@MainActor
final class FertileStoreTests: XCTestCase {
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: anchor)! }
    private var events: [Event] { CycleGenerator.events(startDate: anchor, cycleLength: 28) }
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: "test.fertilestore")!.removePersistentDomain(forName: "test.fertilestore")
        defaults = UserDefaults(suiteName: "test.fertilestore")!
    }

    func testAutoWindowShownWithoutOverrides() {
        let store = FertileStore(defaults: defaults)
        XCTAssertTrue(store.isFertile(day(10), events: events))
        XCTAssertFalse(store.isFertile(day(2), events: events))
    }

    func testToggleAddsAndRemovesDays() {
        let store = FertileStore(defaults: defaults)
        store.toggle(day(2), events: events)
        XCTAssertTrue(store.isFertile(day(2), events: events))
        store.toggle(day(10), events: events)
        XCTAssertFalse(store.isFertile(day(10), events: events))
    }

    func testOverridesPersistAcrossStores() {
        let first = FertileStore(defaults: defaults)
        first.toggle(day(2), events: events)
        let second = FertileStore(defaults: defaults)
        XCTAssertTrue(second.isFertile(day(2), events: events))
    }
}
