import UIKit
import XCTest
@testable import RhythmX

/// The pure logic behind the redesigned Add Tags sheet: the body and rows for a category, search with the
/// custom tag offer, the tray order, the moon intensity labels and VoiceOver strings, the suggested row,
/// the header line, the cycle day and the duplicate rule.
final class TagSheetLogicTests: XCTestCase {
    private let calendar = Calendar.current
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }
    private func pick(_ c: TagCategory, _ v: String) -> TagPick { TagPick(category: c, value: v) }

    // MARK: - Body and rows

    func testEachCategoryHasItsBody() {
        XCTAssertEqual(TagFormLogic.bodyKind(for: .symptom), .intensityRows)
        XCTAssertEqual(TagFormLogic.bodyKind(for: .mood), .moodGrid)
        XCTAssertEqual(TagFormLogic.bodyKind(for: .planning), .planning)
        XCTAssertEqual(TagFormLogic.bodyKind(for: .basalTemp), .basalTemp)
        XCTAssertEqual(TagFormLogic.bodyKind(for: .menopause), .menopause)
        for chips in [TagCategory.dietary, .exercise, .medication, .cervicalMucus, .other] {
            XCTAssertEqual(TagFormLogic.bodyKind(for: chips), .chips, chips.rawValue)
        }
    }

    func testSymptomRowsAreTheLibraryWithIntensityThenPickedCustomTags() {
        var selection = TagSelection()
        selection.add(pick(.symptom, "Sore throat"))
        selection.add(pick(.mood, "Calm"))
        let rows = TagFormLogic.rows(for: .symptom, selection: selection)
        XCTAssertEqual(rows.map(\.pick.value), (TagLibrary.tags[.symptom] ?? []) + ["Sore throat"])
        XCTAssertTrue(rows.allSatisfy { $0.kind == .intensity })
    }

    func testMenopauseRowsCountRepeatableTagsAndRateTheRest() {
        let rows = TagFormLogic.rows(for: .menopause, selection: TagSelection())
        XCTAssertEqual(rows.filter { $0.kind == .counter }.map(\.pick.value), ["Hot Flashes", "Night Sweats"])
        XCTAssertEqual(rows.filter { $0.kind == .intensity }.map(\.pick.value),
                       ["Poor Sleep", "Brain Fog", "Joint Pain", "Vaginal Dryness", "Low Libido", "Heart Palpitations"])
    }

    func testPlanningRowsSplitTheTestStripFromTheToggles() {
        let rows = TagFormLogic.rows(for: .planning, selection: TagSelection())
        XCTAssertEqual(rows.filter { $0.kind == .ovulationTest }.map(\.pick.value),
                       ["Ovulation Test Negative", "Ovulation Test Faint", "Ovulation Test Positive", "Ovulation Test Peak"])
        XCTAssertEqual(rows.filter { $0.kind == .toggle }.map(\.pick.value), ["Intercourse", "Fertility Supplement"])
    }

    func testMoodGridReadsFromBrightToHeavyAndKeepsEveryMood() {
        let rows = TagFormLogic.rows(for: .mood, selection: TagSelection())
        XCTAssertEqual(rows.map(\.pick.value), TagFormLogic.moodGridOrder)
        XCTAssertEqual(Set(rows.map(\.pick.value)), Set(TagLibrary.tags[.mood] ?? []))
    }

    func testChipCategoriesAndMoodAreOneTap() {
        XCTAssertTrue(TagFormLogic.rows(for: .dietary, selection: TagSelection()).allSatisfy { $0.kind == .chip })
        XCTAssertTrue(TagFormLogic.rows(for: .mood, selection: TagSelection()).allSatisfy { $0.kind == .chip })
    }

    func testOnlySymptomAndNonRepeatableMenopauseTagsTakeAStrength() {
        XCTAssertTrue(TagFormLogic.supportsIntensity(pick(.symptom, "Cramps")))
        XCTAssertTrue(TagFormLogic.supportsIntensity(pick(.symptom, "Sore throat")))
        XCTAssertTrue(TagFormLogic.supportsIntensity(pick(.menopause, "Brain Fog")))
        XCTAssertFalse(TagFormLogic.supportsIntensity(pick(.menopause, "Hot Flashes")))
        XCTAssertFalse(TagFormLogic.supportsIntensity(pick(.mood, "Calm")))
        XCTAssertFalse(TagFormLogic.supportsIntensity(pick(.planning, "Intercourse")))
    }

    func testOvulationTestResultsReplaceEachOtherAndTapAgainClears() {
        var selection = TagSelection()
        selection.add(pick(.planning, "Intercourse"))
        TagFormLogic.chooseOvulationTest(pick(.planning, "Ovulation Test Faint"), in: &selection)
        TagFormLogic.chooseOvulationTest(pick(.planning, "Ovulation Test Positive"), in: &selection)
        XCTAssertEqual(selection.items.map(\.pick.value), ["Intercourse", "Ovulation Test Positive"])
        TagFormLogic.chooseOvulationTest(pick(.planning, "Ovulation Test Positive"), in: &selection)
        XCTAssertEqual(selection.items.map(\.pick.value), ["Intercourse"])
    }

    // MARK: - Search

    func testSearchCoversEveryCategoryAndOffersNoCustomTagWhenSomethingMatches() {
        let outcome = TagFormLogic.searchOutcome("fl", mode: .cycle)
        XCTAssertEqual(outcome.groups.map(\.category), [.other, .menopause])
        XCTAssertNil(outcome.customValue)
    }

    func testSearchWithNoMatchOffersTheTextAsACustomTagWithoutEmoji() {
        let outcome = TagFormLogic.searchOutcome("sore throat \u{1F912}", mode: .cycle)
        XCTAssertTrue(outcome.groups.isEmpty)
        XCTAssertEqual(outcome.customValue, "Sore throat")
        XCTAssertEqual(TagFormLogic.customTagTitle("Sore throat"), "Add \u{201C}Sore throat\u{201D} as a custom tag")
        XCTAssertNil(TagFormLogic.searchOutcome("   ", mode: .cycle).customValue)
    }

    func testCustomTagCategoriesPutTheModeFirst() {
        XCTAssertEqual(TagFormLogic.customCategories(for: .cycle), [.symptom, .mood, .medication, .other])
        XCTAssertEqual(TagFormLogic.customCategories(for: .planning), [.planning, .symptom, .mood, .medication, .other])
        XCTAssertEqual(TagFormLogic.customCategories(for: .menopause), [.menopause, .symptom, .mood, .medication, .other])
    }

    // MARK: - Tray

    func testTrayFollowsCategoryOrderThenLibraryOrderThenCustom() {
        var selection = TagSelection()
        selection.add(pick(.mood, "Calm"))
        selection.tap(pick(.symptom, "Breast Tenderness"), level: .light)
        selection.add(pick(.symptom, "Sore throat"))
        selection.tap(pick(.symptom, "Bloating"), level: .medium)
        selection.tap(pick(.symptom, "Cramps"), level: .heavy)
        let tray = TagFormLogic.trayItems(selection, mode: .cycle)
        XCTAssertEqual(tray.map(\.pick.value), ["Cramps", "Bloating", "Breast Tenderness", "Sore throat", "Calm"])
    }

    func testAddButtonTitleCountsEveryTag() {
        XCTAssertEqual(TagFormLogic.addButtonTitle(count: 0), "Add Tags")
        XCTAssertEqual(TagFormLogic.addButtonTitle(count: 1), "Add 1 Tag")
        XCTAssertEqual(TagFormLogic.addButtonTitle(count: 6), "Add 6 Tags")
    }

    func testTrayVoiceOverLabels() {
        XCTAssertEqual(TagFormLogic.trayAccessibilityLabel(.init(pick: pick(.symptom, "Cramps"), count: 1, intensity: .heavy)),
                       "Cramps, Heavy")
        XCTAssertEqual(TagFormLogic.trayAccessibilityLabel(.init(pick: pick(.menopause, "Hot Flashes"), count: 3)),
                       "Hot Flashes, 3 times")
        XCTAssertEqual(TagFormLogic.trayAccessibilityLabel(.init(pick: pick(.mood, "Calm"), count: 1)), "Calm")
    }

    // MARK: - Intensity

    func testIntensityValueAndAdjustingForVoiceOver() {
        XCTAssertEqual(TagFormLogic.intensityValue(nil), "Off")
        XCTAssertEqual(TagFormLogic.intensityValue(.light), "Light")
        XCTAssertEqual(TagFormLogic.intensityValue(.medium), "Medium")
        XCTAssertEqual(TagFormLogic.intensityValue(.heavy), "Heavy")
        XCTAssertEqual(TagFormLogic.adjusted(nil, up: true), .light)
        XCTAssertEqual(TagFormLogic.adjusted(.light, up: true), .medium)
        XCTAssertEqual(TagFormLogic.adjusted(.heavy, up: true), .heavy)
        XCTAssertEqual(TagFormLogic.adjusted(.light, up: false), nil)
        XCTAssertEqual(TagFormLogic.adjusted(nil, up: false), nil)
    }

    func testSettingALevelDirectlyAndClearingIt() {
        var selection = TagSelection()
        let cramps = pick(.symptom, "Cramps")
        selection.set(cramps, level: .medium)
        selection.set(cramps, level: .heavy)
        XCTAssertEqual(selection.intensity(of: cramps), .heavy)
        XCTAssertEqual(selection.totalCount, 1)
        selection.set(cramps, level: nil)
        XCTAssertTrue(selection.isEmpty)
    }

    // MARK: - Suggested row

    func testSuggestedRowPutsHistoryFirstThenPhasePicksWithoutRepeats() throws {
        let row = try XCTUnwrap(TagFormLogic.suggestedRow(phase: .luteal, mode: .cycle,
                                                          history: [pick(.symptom, "Bloating"), pick(.symptom, "Breast Tenderness")]))
        XCTAssertEqual(row.title, "For your luteal phase")
        XCTAssertEqual(row.picks.map(\.value), ["Bloating", "Breast Tenderness", "Mood Swings", "Food Cravings", "PMS"])
    }

    func testSuggestedRowForPlanningAndMenopause() throws {
        let planning = try XCTUnwrap(TagFormLogic.suggestedRow(phase: .follicular, mode: .planning, history: []))
        XCTAssertTrue(planning.picks.contains(pick(.planning, "Ovulation Test Positive")))
        XCTAssertTrue(planning.picks.contains(pick(.cervicalMucus, "Egg White")))
        let menopause = try XCTUnwrap(TagFormLogic.suggestedRow(phase: nil, mode: .menopause, history: []))
        XCTAssertEqual(menopause.title, "Common in menopause")
        XCTAssertEqual(menopause.picks.first, pick(.menopause, "Hot Flashes"))
        XCTAssertNil(TagFormLogic.suggestedRow(phase: nil, mode: .cycle, history: []))
    }

    // MARK: - Header, cycle day, logging rules

    func testCycleDayCountsFromThePeriodStartOnOrBeforeTheDay() {
        let events = CycleGenerator.events(startDate: day(-25), cycleLength: 28)
        XCTAssertEqual(TagFormLogic.cycleDay(on: now, events: events), 26)
        XCTAssertEqual(TagFormLogic.cycleDay(on: day(-25), events: events), 1)
        XCTAssertNil(TagFormLogic.cycleDay(on: day(10), events: events))
        let menopause = [Event(eventType: .follicular, date: now, note: "", mode: .menopause)]
        XCTAssertNil(TagFormLogic.cycleDay(on: now, events: menopause))
    }

    func testHeaderSubtitlePerMode() {
        XCTAssertEqual(TagFormLogic.headerSubtitle(dateText: "Tue, Oct 20", cycleDay: 26, phase: .luteal, mode: .cycle),
                       "Tue, Oct 20 \u{00B7} Day 26 \u{00B7} Luteal")
        XCTAssertEqual(TagFormLogic.headerSubtitle(dateText: "Tue, Oct 20", cycleDay: 26, phase: .luteal, mode: .planning),
                       "Tue, Oct 20 \u{00B7} Day 26 \u{00B7} Planning")
        XCTAssertEqual(TagFormLogic.headerSubtitle(dateText: "Tue, Oct 20", cycleDay: nil, phase: nil, mode: .menopause),
                       "Tue, Oct 20 \u{00B7} Menopause")
        XCTAssertEqual(TagFormLogic.headerSubtitle(dateText: "Tue, Oct 20", cycleDay: nil, phase: nil, mode: .cycle),
                       "Tue, Oct 20 \u{00B7} No cycle day")
    }

    func testOnlyMenopauseOrACycleDayCanHoldTags() {
        let events = CycleGenerator.events(startDate: day(-5), cycleLength: 28)
        XCTAssertTrue(TagFormLogic.canHoldTags(on: now, mode: .cycle, events: events))
        XCTAssertFalse(TagFormLogic.canHoldTags(on: day(40), mode: .planning, events: events))
        XCTAssertTrue(TagFormLogic.canHoldTags(on: day(40), mode: .menopause, events: events))
        let carrier = [Event(eventType: .follicular, date: now, note: "", mode: .menopause)]
        XCTAssertFalse(TagFormLogic.canHoldTags(on: now, mode: .cycle, events: carrier))
    }

    func testADuplicateBlocksTheSaveUnlessItChangesTheLevel() {
        let items: [TagSelection.Item] = [
            .init(pick: pick(.symptom, "Cramps"), count: 1, intensity: .heavy),     // logged medium: a level change
            .init(pick: pick(.symptom, "Bloating"), count: 1, intensity: .medium),  // logged medium: same level
            .init(pick: pick(.mood, "Calm"), count: 1),                             // logged, no level
            .init(pick: pick(.mood, "Happy"), count: 1),                            // new
        ]
        let logged: [String: TagIntensity?] = ["Symptom:Cramps": .medium, "Symptom:Bloating": .medium, "Mood:Calm": nil]
        let blocked = TagFormLogic.blockedDuplicates(items, isDuplicate: { logged.keys.contains($0) },
                                                     storedLevel: { logged[$0] ?? nil })
        XCTAssertEqual(blocked.map(\.pick.value), ["Bloating", "Calm"])
    }

    func testMoonSegmentsHaveA44PointHitArea() {
        XCTAssertGreaterThanOrEqual(MoonIntensityControl.hitHeight, 44)
        XCTAssertEqual(MoonIntensityControl.segmentHeight + 2 * MoonIntensityControl.hitPadding, MoonIntensityControl.hitHeight)
        XCTAssertGreaterThanOrEqual(MoonIntensityControl.segmentWidth, 44)
    }

    func testCounterSubtitle() {
        XCTAssertEqual(TagFormLogic.loggedCountText(0), "None logged yet this day")
        XCTAssertEqual(TagFormLogic.loggedCountText(1), "Logged once this day")
        XCTAssertEqual(TagFormLogic.loggedCountText(3), "Logged 3 times this day")
    }

    func testOvulationTestShortNamesAndTheInfoText() {
        XCTAssertEqual(TagFormLogic.ovulationTestShortName("Ovulation Test Peak"), "Peak")
        XCTAssertEqual(ModeGuideContent.ovulationTestExplanation,
                       "Ovulation tests are at-home test strips that detect the hormone surge that comes a day or two before ovulation. Log the result you see: Negative, Faint, Positive or Peak.")
    }

    func testEveryTagGlyphIsARealSymbol() {
        for (raw, name) in TagGlyph.symbols {
            XCTAssertNotNil(UIImage(systemName: name), "\(raw): \(name)")
        }
        XCTAssertEqual(TagGlyph.symbol(for: pick(.planning, "Ovulation Test Peak")), "testtube.2")
        XCTAssertEqual(TagGlyph.symbol(for: pick(.exercise, "Yoga")), TagCategory.exercise.symbolName)
    }
}
