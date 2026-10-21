import XCTest
@testable import RhythmX

final class InsightRevealTests: XCTestCase {

    func testNothingShowsBeforeTheSheetSettles() {
        let reveal = InsightReveal(lineCount: 3)
        XCTAssertEqual(reveal.lineProgress(0, at: 0), 0)
        XCTAssertEqual(reveal.curveProgress(at: 0), 0)
        XCTAssertEqual(reveal.glow(at: 0), 0)
        XCTAssertEqual(reveal.chipsProgress(at: 0), 0)
    }

    func testLinesRevealInOrderAndEachReachesOne() {
        let reveal = InsightReveal(lineCount: 3)
        let t = InsightReveal.settle + InsightReveal.lineDuration + 0.01
        XCTAssertEqual(reveal.lineProgress(0, at: t), 1, accuracy: 0.001)
        XCTAssertGreaterThan(reveal.lineProgress(1, at: t), 0)
        XCTAssertLessThan(reveal.lineProgress(1, at: t), 1)
        XCTAssertEqual(reveal.lineProgress(2, at: t), 0)
        for line in 0..<3 { XCTAssertEqual(reveal.lineProgress(line, at: reveal.textEnd), 1) }
    }

    func testCurveDrawsAfterTheTextThenTheMarkerGlowsAndSettlesLit() {
        let reveal = InsightReveal(lineCount: 2)
        XCTAssertEqual(reveal.curveProgress(at: reveal.textEnd), 0)
        XCTAssertGreaterThan(reveal.curveProgress(at: reveal.textEnd + InsightReveal.curveDuration / 2), 0.2)
        XCTAssertEqual(reveal.curveProgress(at: reveal.curveEnd), 1)
        XCTAssertEqual(reveal.glow(at: reveal.curveEnd - 0.01), 0)
        XCTAssertGreaterThan(reveal.glow(at: reveal.curveEnd + InsightReveal.glowDuration / 4), 0.9)
        XCTAssertEqual(reveal.glow(at: reveal.total), 1)
        XCTAssertEqual(reveal.glow(at: reveal.total + 10), 1)
    }

    func testTheMarkerGlowsTwice() {
        let reveal = InsightReveal(lineCount: 1)
        let samples = stride(from: reveal.curveEnd, through: reveal.total, by: 0.01).map { reveal.glow(at: $0) }
        var peaks = 0
        for i in 1..<(samples.count - 1) where samples[i] > samples[i - 1] && samples[i] >= samples[i + 1] && samples[i] > 0.95 {
            peaks += 1
        }
        XCTAssertEqual(peaks, 2)
    }

    func testChipsArriveWithTheCurve() {
        let reveal = InsightReveal(lineCount: 2)
        XCTAssertEqual(reveal.chipsProgress(at: reveal.textEnd), 0)
        XCTAssertEqual(reveal.chipsProgress(at: reveal.total), 1)
    }

    func testProgressMapsOntoTheTimeline() {
        let reveal = InsightReveal(lineCount: 3)
        XCTAssertEqual(reveal.elapsed(forProgress: 0), 0)
        XCTAssertEqual(reveal.elapsed(forProgress: 1), reveal.total)
        XCTAssertEqual(reveal.elapsed(forProgress: 2), reveal.total)
        XCTAssertEqual(reveal.elapsed(forProgress: -1), 0)
    }

    func testStreamedTextMovesTheCurveToWhenTheStreamEnded() {
        let reveal = InsightReveal(lineCount: 3, textEnd: 4)
        XCTAssertEqual(reveal.textEnd, 4)
        XCTAssertEqual(reveal.curveProgress(at: 3.9), 0)
        XCTAssertEqual(reveal.curveEnd, 4 + InsightReveal.curveDuration)
    }

    func testAtLeastOneLine() {
        XCTAssertEqual(InsightReveal(lineCount: 0).lineCount, 1)
    }

    func testEstimatedLinesWrapOnWords() {
        XCTAssertEqual(InsightReveal.estimatedLines("", charactersPerLine: 10), 1)
        XCTAssertEqual(InsightReveal.estimatedLines("short", charactersPerLine: 10), 1)
        XCTAssertEqual(InsightReveal.estimatedLines("aaaa bbbb cccc", charactersPerLine: 10), 2)
        XCTAssertEqual(InsightReveal.estimatedLines("Sweet cravings showed up on days 24 to 27 in 4 of your last 5 cycles. Today is day 26.",
                                                    charactersPerLine: 34), 3)
    }

    func testShimmerRidesTheLeadingEdgeAndLeavesWhenTheLineIsDone() {
        XCTAssertNil(InsightReveal.shimmerCenter(lineProgress: 0))
        XCTAssertNil(InsightReveal.shimmerCenter(lineProgress: 1))
        XCTAssertEqual(InsightReveal.shimmerCenter(lineProgress: 0.5) ?? -1, 0.5, accuracy: 1e-9)
    }
}
