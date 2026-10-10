import XCTest
@testable import RhythmX

final class MoonPhaseTests: XCTestCase {
    func testPhaseToMoonMapping() {
        XCTAssertEqual(Event.EventType.menstrual.moonPhase, .new)
        XCTAssertEqual(Event.EventType.follicular.moonPhase, .crescent)
        XCTAssertEqual(Event.EventType.ovulation.moonPhase, .full)
        XCTAssertEqual(Event.EventType.luteal.moonPhase, .waning)
    }
}
