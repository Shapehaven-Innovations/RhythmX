import XCTest
@testable import RhythmX

final class PhaseGuideTests: XCTestCase {

    func testFourEntriesInPhaseOrder() {
        XCTAssertEqual(PhaseGuideContent.raw.count, 4)
        let headings = PhaseGuideContent.raw.map { PhaseGuideParser.parse($0).heading }
        XCTAssertEqual(headings[0], "1. Menstrual Phase")
        XCTAssertEqual(headings[1], "2. Follicular Phase")
        XCTAssertEqual(headings[2], "3. Ovulatory Phase")
        XCTAssertEqual(headings[3], "4. Luteal Phase")
    }

    func testParsedTextLosesNothingAndChangesNothing() {
        for raw in PhaseGuideContent.raw {
            let e = PhaseGuideParser.parse(raw)
            let flattened = [e.heading] + e.timing + e.sections.flatMap { [$0.title] + $0.lines }
            let original = raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            XCTAssertEqual(flattened, original)
        }
    }

    func testEachEntryHasTimingAndSections() {
        for raw in PhaseGuideContent.raw {
            let e = PhaseGuideParser.parse(raw)
            XCTAssertFalse(e.timing.isEmpty)
            XCTAssertTrue(e.timing[0].hasPrefix("Approximate Timing"))
            XCTAssertGreaterThanOrEqual(e.sections.count, 3)
            XCTAssertTrue(e.sections.allSatisfy { !$0.lines.isEmpty })
        }
    }
}
