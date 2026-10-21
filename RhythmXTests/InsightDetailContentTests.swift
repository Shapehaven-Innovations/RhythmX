import XCTest
@testable import RhythmX

final class InsightDetailContentTests: XCTestCase {

    private let bloating = TagPick(category: .symptom, value: "Bloating")
    private let cravings = TagPick(category: .symptom, value: "Food Cravings")
    private let tender = TagPick(category: .symptom, value: "Breast Tenderness")
    private let fatigue = TagPick(category: .symptom, value: "Fatigue")
    private let sweet = TagPick(category: .dietary, value: "Sweet Craving")
    private let allKinds = Set(ShareCard.Kind.allCases)

    private func make(_ kind: DailyInsightTile.Kind, mode: TrackingMode, phase: Event.EventType? = .luteal,
                      day: Int? = 26, length: Int = 28, weeks: [Int] = [], choices: [TagPick]? = nil,
                      patternPick: TagPick? = nil, kinds: Set<ShareCard.Kind>? = nil) -> InsightDetailContent {
        InsightDetailContent.make(tile: DailyInsightTile(kind: kind, title: "Title", body: "Body"), mode: mode,
                                  phase: phase, cycleDay: day, cycleLength: length, hotFlashWeeks: weeks,
                                  choices: choices ?? [bloating, cravings, tender, fatigue], patternPick: patternPick,
                                  shareKinds: kinds ?? allKinds)
    }

    func testCycleShowsTheHormoneCurveAtTodayWithoutTheFertileBand() {
        let content = make(.pattern, mode: .cycle)
        XCTAssertEqual(content.chart, .hormones(day: 26, length: 28, fertileBand: nil))
        XCTAssertFalse(content.showsFertilityLine)
        XCTAssertEqual(content.eyebrow, "Day 26 · Luteal")
    }

    func testPlanningShowsTheFertileBandAndTheBirthControlLine() {
        let content = make(.cycleDay, mode: .planning, phase: .follicular, day: 6)
        XCTAssertEqual(content.chart, .hormones(day: 6, length: 28, fertileBand: 9...16))
        XCTAssertTrue(content.showsFertilityLine)
    }

    func testTheFertileTileAlwaysCarriesTheBirthControlLine() {
        XCTAssertTrue(make(.fertile, mode: .planning).showsFertilityLine)
    }

    func testMenopauseShowsAnEightWeekTrendAndNoCycleNumbers() {
        let content = make(.menopauseSymptoms, mode: .menopause, phase: .luteal, day: 26, weeks: [1, 2, 3])
        XCTAssertEqual(content.chart, .menopauseTrend(weeks: [0, 0, 0, 0, 0, 1, 2, 3]))
        XCTAssertFalse(content.showsFertilityLine)
        XCTAssertFalse(content.eyebrow.contains("Day"))
        XCTAssertFalse(content.eyebrow.contains("Luteal"))
    }

    func testMenopauseTrendKeepsTheLastEightWeeks() {
        let content = make(.sleep, mode: .menopause, weeks: Array(1...10))
        XCTAssertEqual(content.chart, .menopauseTrend(weeks: Array(3...10)))
    }

    func testNoCycleDayMeansNoCurve() {
        XCTAssertEqual(make(.energy, mode: .cycle, phase: nil, day: nil).chart, InsightDetailContent.Chart.none)
    }

    func testLengthIsClampedForTheCurve() {
        XCTAssertEqual(make(.pattern, mode: .cycle, day: 30, length: 60).chart,
                       .hormones(day: 30, length: 45, fertileBand: nil))
    }

    func testChipsAreThreeAtMostWithThePatternTagFirst() {
        let content = make(.pattern, mode: .cycle, choices: [bloating, sweet, cravings, tender], patternPick: sweet)
        XCTAssertEqual(content.chips, [sweet, bloating, cravings])
        XCTAssertEqual(content.primaryChip, sweet)
        XCTAssertEqual(content.primaryTitle, "Log Sweet Craving")
    }

    func testOtherTilesUseTheChoicesAsTheyCome() {
        let content = make(.energy, mode: .cycle, patternPick: sweet)
        XCTAssertEqual(content.chips, [bloating, cravings, tender])
    }

    func testWithoutChipsThePrimaryButtonOpensAddTag() {
        let content = make(.energy, mode: .cycle, choices: [])
        XCTAssertNil(content.primaryChip)
        XCTAssertEqual(content.primaryTitle, "Log a Tag")
    }

    func testShareUsesTheMatchingCard() {
        XCTAssertEqual(make(.cycleDay, mode: .cycle).shareKind, .cycleDay)
        XCTAssertEqual(make(.possibleToday, mode: .cycle).shareKind, .possibleToday)
        XCTAssertEqual(make(.energy, mode: .cycle).shareKind, .phase)
        XCTAssertEqual(make(.pattern, mode: .cycle).shareKind, .combined)
        XCTAssertEqual(make(.fertile, mode: .planning).shareKind, .bestChances)
        XCTAssertEqual(make(.menopauseSymptoms, mode: .menopause).shareKind, .hotFlashes)
        XCTAssertEqual(make(.sleep, mode: .menopause).shareKind, .combined)
    }

    func testShareFallsBackToAnOfferedCardOrNone() {
        XCTAssertEqual(make(.fertile, mode: .planning, kinds: [.cycleDay, .combined]).shareKind, .combined)
        XCTAssertNil(make(.cycleDay, mode: .cycle, kinds: []).shareKind)
    }

    func testFootersArePlain() {
        XCTAssertEqual(InsightDetailContent.footer, "It can be wrong. Tracking tool, not medical advice.")
        XCTAssertEqual(InsightDetailContent.fertilityFooter, "Predictions are estimates and are not birth control.")
        XCTAssertEqual(InsightDetailContent.curveCaption, "Typical pattern, estimates only")
        for text in [InsightDetailContent.footer, InsightDetailContent.fertilityFooter, InsightDetailContent.curveCaption] {
            XCTAssertFalse(text.contains("\u{2014}"))
        }
    }
}
