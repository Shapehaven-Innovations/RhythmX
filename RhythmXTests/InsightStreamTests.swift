import XCTest
@testable import RhythmX

/// A stand-in for the on-device model: yields the given snapshots, then optionally fails.
private struct FakeStreamer: InsightTileStreaming {
    var isAvailable = true
    var snapshots: [String]
    var failsAtEnd = false

    func stream(kind: DailyInsightTile.Kind, facts: InsightFacts) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for snapshot in snapshots { continuation.yield(snapshot) }
            continuation.finish(throwing: failsAtEnd ? InsightGenerationError.unavailable : nil)
        }
    }
}

final class InsightStreamTests: XCTestCase {

    private let facts = InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 26, daysUntilPeriod: 3,
                                     recentTags: [.init(label: "Sweet Craving", count: 4)],
                                     pattern: .init(label: "Sweet Craving",
                                                    sentence: "Sweet Craving came on day 24 to 27, in 4 of your last 5 cycles."))

    private func run(_ streamer: FakeStreamer, kind: DailyInsightTile.Kind = .pattern) async -> (InsightStreamResult, [String]) {
        var partials: [String] = []
        let result = await InsightTileStreamRunner.run(streamer: streamer, kind: kind, facts: facts,
                                                       fallback: "Template text.") { partials.append($0) }
        return (result, partials)
    }

    func testAValidStreamIsShownAsItArrivesAndKeptAsWrittenOnThisDevice() async {
        let (result, partials) = await run(FakeStreamer(snapshots: ["Sweet", "Sweet cravings came on day 24",
                                                                    "Sweet cravings came on day 24 to 27 in 4 of your last 5 cycles."]))
        XCTAssertEqual(partials.count, 3)
        XCTAssertEqual(result, InsightStreamResult(text: "Sweet cravings came on day 24 to 27 in 4 of your last 5 cycles.", isAI: true))
    }

    func testAnUnfinishedNumberIsNotRejectedMidStream() async {
        // "2" is not an allowed number on its own, but it is the start of "24".
        let (result, _) = await run(FakeStreamer(snapshots: ["On day 2", "On day 24 you often log Sweet Craving."]))
        XCTAssertTrue(result.isAI)
    }

    func testABlockedWordMidStreamStopsAndFallsBackToTheTemplate() async {
        let (result, partials) = await run(FakeStreamer(snapshots: ["You should see a doctor", "You should see a doctor soon."]))
        XCTAssertEqual(result, InsightStreamResult(text: "Template text.", isAI: false))
        XCTAssertTrue(partials.isEmpty)
    }

    func testAFinalTextThatFailsTheValidatorFallsBack() async {
        let (result, _) = await run(FakeStreamer(snapshots: ["Sweet cravings came in 9 of your cycles."]))
        XCTAssertEqual(result, InsightStreamResult(text: "Template text.", isAI: false))
    }

    func testAnErrorFallsBack() async {
        let (result, _) = await run(FakeStreamer(snapshots: ["Sweet cravings"], failsAtEnd: true))
        XCTAssertEqual(result, InsightStreamResult(text: "Template text.", isAI: false))
    }

    func testAnEmptyStreamFallsBack() async {
        let (result, _) = await run(FakeStreamer(snapshots: []))
        XCTAssertFalse(result.isAI)
    }

    func testUnavailableModelFallsBackWithoutStreaming() async {
        let (result, partials) = await run(FakeStreamer(isAvailable: false, snapshots: ["Sweet cravings came on day 24."]))
        XCTAssertEqual(result, InsightStreamResult(text: "Template text.", isAI: false))
        XCTAssertTrue(partials.isEmpty)
    }

    func testOnlyTheModelWrittenTilesStream() {
        XCTAssertTrue(InsightTileStreamRunner.streams(kind: .pattern, facts: facts))
        XCTAssertTrue(InsightTileStreamRunner.streams(kind: .energy, facts: facts))
        XCTAssertFalse(InsightTileStreamRunner.streams(kind: .cycleDay, facts: facts))
        XCTAssertFalse(InsightTileStreamRunner.streams(kind: .fertile, facts: facts))
        XCTAssertFalse(InsightTileStreamRunner.streams(kind: .pattern, facts: InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 26)))
    }

    func testTheTilePromptAsksForOneFieldFromTheFactsOnly() {
        let prompt = FoundationModelsInsightWriter.tilePrompt(for: facts, kind: .pattern)
        XCTAssertTrue(prompt.contains("Pattern: Sweet Craving came on day 24 to 27"))
        XCTAssertTrue(prompt.contains("text: the pattern in your own words"))
        XCTAssertFalse(prompt.contains("moodLine"))
        let energy = FoundationModelsInsightWriter.tilePrompt(for: facts, kind: .energy)
        XCTAssertTrue(energy.contains("text: one or two sentences about energy"))
    }

    func testPartialCheckAllowsTheStartOfAnAllowedText() {
        XCTAssertTrue(InsightTileStreamRunner.isAcceptablePartial("", facts: facts))
        XCTAssertTrue(InsightTileStreamRunner.isAcceptablePartial("Day 2", facts: facts))
        XCTAssertFalse(InsightTileStreamRunner.isAcceptablePartial("Day 9 and", facts: facts))
        XCTAssertFalse(InsightTileStreamRunner.isAcceptablePartial("A goddess", facts: facts))
        XCTAssertFalse(InsightTileStreamRunner.isAcceptablePartial(String(repeating: "a", count: 141), facts: facts))
    }
}
