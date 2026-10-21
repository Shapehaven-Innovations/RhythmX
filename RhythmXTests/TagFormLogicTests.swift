import UIKit
import XCTest
@testable import RhythmX

/// The pure logic behind the Add Tag page: tag strings, the selection tray, search, suggestions,
/// the Recent row and the archive-based Smart Tags.
final class TagFormLogicTests: XCTestCase {
    private let calendar = Calendar.current
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }

    private func block(_ phase: Event.EventType, tags: [String], mode: TrackingMode? = nil) -> ArchivedDataBlock {
        let events = tags.enumerated().map { index, t in Event(eventType: phase, date: day(-100 - index), note: "", tags: t) }
        return ArchivedDataBlock(date: day(-120), groupedEvents: [.init(eventType: phase, events: events)], mode: mode)
    }

    // MARK: - Tag strings

    func testTagStringKeepsTheStoredFormat() {
        XCTAssertEqual(TagFormLogic.tagString(category: .symptom, value: "  cramps "), "Symptom:Cramps")
        XCTAssertEqual(TagFormLogic.tagString(category: .basalTemp, value: "97.8"), "Basal Temp:97.8")
        XCTAssertEqual(TagFormLogic.tagString(category: .dietary, value: "   "), "Dietary:unspecified")
        XCTAssertEqual(TagPick(category: .planning, value: "Ovulation Test Peak").raw, "Planning:Ovulation Test Peak")
    }

    func testCustomPickCapitalizesAndRejectsBlank() {
        XCTAssertEqual(TagFormLogic.customPick(category: .mood, text: " tired "), TagPick(category: .mood, value: "Tired"))
        XCTAssertNil(TagFormLogic.customPick(category: .mood, text: "  \n"))
    }

    func testEmojiAreDroppedFromTypedTags() {
        XCTAssertEqual(TagFormLogic.removingEmoji("Chocolate \u{1F36B}"), "Chocolate ")
        XCTAssertEqual(TagFormLogic.removingEmoji("\u{2764}\u{FE0F} love"), " love")
        XCTAssertEqual(TagFormLogic.removingEmoji("\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}x"), "x")
        XCTAssertEqual(TagFormLogic.removingEmoji("\u{1F44D}\u{1F3FD}ok"), "ok")
        for plain in ["97.8", "#1 Day", "Caf\u{E9} 2*3", "Back Pain"] {
            XCTAssertEqual(TagFormLogic.removingEmoji(plain), plain)
        }
        XCTAssertEqual(TagFormLogic.customPick(category: .dietary, text: "\u{1F36B} chocolate"),
                       TagPick(category: .dietary, value: "Chocolate"))
        XCTAssertNil(TagFormLogic.customPick(category: .dietary, text: "\u{1F36B}\u{1F36B}"))
    }

    func testPickFromRawMatchesSmartTagRules() {
        XCTAssertEqual(TagFormLogic.pick(fromRaw: "symptom: Cramps"), TagPick(category: .symptom, value: "Cramps"))
        XCTAssertEqual(TagFormLogic.pick(fromRaw: "Cervical Mucus:Egg White"), TagPick(category: .cervicalMucus, value: "Egg White"))
        XCTAssertEqual(TagFormLogic.pick(fromRaw: "Weird:Thing"), TagPick(category: .other, value: "Thing"))
        XCTAssertEqual(TagFormLogic.pick(fromRaw: "No colon"), TagPick(category: .other, value: "No colon"))
    }

    // MARK: - Selection tray

    func testNormalTagIsOnePerSave() {
        var s = TagSelection()
        let cramps = TagPick(category: .symptom, value: "Cramps")
        s.toggle(cramps)
        XCTAssertEqual(s.count(of: cramps), 1)
        s.increment(cramps)
        XCTAssertEqual(s.count(of: cramps), 1, "a normal tag cannot be added twice")
        s.toggle(cramps)
        XCTAssertTrue(s.isEmpty)
    }

    func testRepeatableTagCountsUpAndDown() {
        var s = TagSelection()
        let flash = TagPick(category: .menopause, value: "Hot Flashes")
        s.toggle(flash)
        s.increment(flash)
        s.increment(flash)
        XCTAssertEqual(s.count(of: flash), 3)
        XCTAssertEqual(s.rawTagsToLog, ["Menopause:Hot Flashes", "Menopause:Hot Flashes", "Menopause:Hot Flashes"])
        s.decrement(flash)
        XCTAssertEqual(s.count(of: flash), 2)
        s.decrement(flash); s.decrement(flash)
        XCTAssertTrue(s.isEmpty)
    }

    func testLegacyOtherHotFlashesIsNotRepeatable() {
        var s = TagSelection()
        let legacy = TagPick(category: .other, value: "Hot Flashes")
        s.toggle(legacy)
        s.increment(legacy)
        XCTAssertEqual(s.count(of: legacy), 1)
    }

    func testTrayKeepsPickOrderAndTotal() {
        var s = TagSelection()
        s.toggle(TagPick(category: .mood, value: "Calm"))
        s.toggle(TagPick(category: .menopause, value: "Night Sweats"))
        s.increment(TagPick(category: .menopause, value: "Night Sweats"))
        s.add(TagPick(category: .mood, value: "Calm"))
        XCTAssertEqual(s.items.map(\.pick.value), ["Calm", "Night Sweats"])
        XCTAssertEqual(s.totalCount, 3)
        XCTAssertEqual(s.rawTagsToLog, ["Mood:Calm", "Menopause:Night Sweats", "Menopause:Night Sweats"])
    }

    // MARK: - Search

    func testSearchFindsTagsAcrossAllCategories() {
        let results = TagFormLogic.search("sweat", categories: TagCategory.allCases)
        XCTAssertEqual(results.map(\.category), [.other, .menopause])
        XCTAssertTrue(results.allSatisfy { $0.values == ["Night Sweats"] })
    }

    func testSearchMatchesCategoryNameAndIgnoresCase() {
        let results = TagFormLogic.search("MUCUS", categories: TagLibrary.categories(for: .planning))
        XCTAssertEqual(results.first?.category, .cervicalMucus)
        XCTAssertEqual(results.first?.values, TagLibrary.tags[.cervicalMucus])
        XCTAssertTrue(TagFormLogic.search("  ", categories: TagCategory.allCases).isEmpty)
        XCTAssertTrue(TagFormLogic.search("zzzz", categories: TagCategory.allCases).isEmpty)
    }

    func testCategoryOrderPutsTheModeFirstAndKeepsEveryCategory() {
        for mode in TrackingMode.allCases {
            let order = TagFormLogic.orderedCategories(for: mode)
            XCTAssertEqual(Array(order.prefix(TagLibrary.categories(for: mode).count)), TagLibrary.categories(for: mode))
            XCTAssertEqual(Set(order), Set(TagCategory.allCases))
            XCTAssertEqual(order.count, TagCategory.allCases.count)
        }
    }

    func testEveryCategoryHasADistinctSystemSymbol() {
        let names = TagCategory.allCases.map(\.symbolName)
        XCTAssertEqual(Set(names).count, names.count)
        for name in names { XCTAssertNotNil(UIImage(systemName: name), name) }
    }

    // MARK: - Suggestions

    func testPhaseSuggestionsKeepTheirCategories() {
        let luteal = TagFormLogic.suggestionGroups(phase: .luteal, mode: .cycle)
        let picks = luteal.first?.picks ?? []
        XCTAssertEqual(picks.map(\.value), ["Mood Swings", "Breast Tenderness", "Food Cravings", "PMS"])
        XCTAssertEqual(picks.first?.category, .mood, "a known mood tag goes under Mood")
        XCTAssertEqual(picks.last?.category, .symptom, "everything else goes under Symptom")
        let menstrual = TagFormLogic.suggestionGroups(phase: .menstrual, mode: .cycle).first?.picks ?? []
        XCTAssertEqual(menstrual.first { $0.value == "Irritable" }?.category, .mood)
    }

    func testFertilePhasesSuggestCervicalMucusAndPlanningSuggestsOvulationTests() {
        let cycle = TagFormLogic.suggestionGroups(phase: .ovulation, mode: .cycle)
        XCTAssertTrue(cycle.contains { $0.picks.map(\.value) == TagLibrary.tags[.cervicalMucus] })
        XCTAssertFalse(cycle.contains { $0.picks.contains { $0.category == .planning } })

        let planning = TagFormLogic.suggestionGroups(phase: .follicular, mode: .planning)
        let tests = planning.first { $0.picks.contains { $0.value == "Ovulation Test Peak" } }
        XCTAssertEqual(tests?.picks.map(\.category), Array(repeating: .planning, count: 4))

        XCTAssertFalse(TagFormLogic.suggestionGroups(phase: .luteal, mode: .cycle)
            .contains { $0.picks.contains { $0.category == .cervicalMucus } })
    }

    func testMenopauseWithNoPhaseSuggestsMenopauseTags() {
        let groups = TagFormLogic.suggestionGroups(phase: nil, mode: .menopause)
        let picks = groups.flatMap(\.picks)
        XCTAssertFalse(picks.isEmpty)
        XCTAssertTrue(picks.allSatisfy { $0.category == .menopause && (TagLibrary.tags[.menopause] ?? []).contains($0.value) })
        XCTAssertTrue(TagFormLogic.suggestionGroups(phase: nil, mode: .cycle).isEmpty)
    }

    // MARK: - Recent

    func testRecentPutsTheLatestFirstThenTheMostFrequent() {
        let events = [
            Event(eventType: .menstrual, date: day(-10), note: "", tags: "Symptom:Cramps, Mood:Calm"),
            Event(eventType: .menstrual, date: day(-9), note: "", tags: "Symptom:Cramps"),
            Event(eventType: .follicular, date: day(-2), note: "", tags: "Exercise:Yoga, Mood:Calm"),
            Event(eventType: .follicular, date: day(-2), note: "", tags: "Symptom:Cramps"),
        ]
        let recent = TagFormLogic.recentTags(events: events, mode: .cycle, now: now)
        XCTAssertEqual(recent.map(\.raw), ["Symptom:Cramps", "Mood:Calm", "Exercise:Yoga"])
    }

    func testRecentSkipsFutureOldOtherModeAndTemperatureValues() {
        let events = [
            Event(eventType: .luteal, date: day(5), note: "", tags: "Symptom:Future"),
            Event(eventType: .luteal, date: day(-200), note: "", tags: "Symptom:Ancient"),
            Event(eventType: .follicular, date: day(-1), note: "", tags: "Menopause:Hot Flashes", mode: .menopause),
            Event(eventType: .follicular, date: day(-1), note: "", tags: "Basal Temp:97.8, Basal Temp:Elevated BBT"),
            Event(eventType: .follicular, date: day(-1), note: "", tags: "Planning:Intercourse", mode: .planning),
        ]
        XCTAssertEqual(TagFormLogic.recentTags(events: events, mode: .cycle, now: now).map(\.raw),
                       ["Basal Temp:Elevated BBT", "Planning:Intercourse"])
        XCTAssertEqual(TagFormLogic.recentTags(events: events, mode: .menopause, now: now).map(\.raw),
                       ["Menopause:Hot Flashes"])
    }

    func testRecentIsCappedAndEmptyWithNoEvents() {
        XCTAssertTrue(TagFormLogic.recentTags(events: [], mode: .cycle, now: now).isEmpty)
        let many = (0..<20).map { Event(eventType: .luteal, date: day(-$0), note: "", tags: "Other:Tag \($0)") }
        XCTAssertEqual(TagFormLogic.recentTags(events: many, mode: .cycle, now: now, limit: 8).count, 8)
    }

    // MARK: - Smart Tags (archive, cycle blocks only)

    func testSmartTagsRankArchiveTagsThenFillFromLibrary() {
        let blocks = [block(.luteal, tags: ["Symptom:Cramps, Mood:Calm", "Symptom:Cramps"]),
                      block(.menstrual, tags: ["Symptom:Headache"])]
        let smart = TagFormLogic.smartTags(phase: .luteal, blocks: blocks, category: .exercise)
        XCTAssertEqual(Array(smart.prefix(2)), ["Symptom:Cramps", "Mood:Calm"])
        XCTAssertEqual(smart.count, 8)
        XCTAssertEqual(smart[2], "Exercise:Light Walk")
        XCTAssertEqual(TagFormLogic.historyTags(phase: .luteal, blocks: blocks), ["Symptom:Cramps", "Mood:Calm"])
    }

    func testSmartTagsWithNoPhaseAreTheCategoryLibrary() {
        let blocks = [block(.luteal, tags: ["Symptom:Cramps"])]
        XCTAssertEqual(TagFormLogic.smartTags(phase: nil, blocks: blocks, category: .cervicalMucus),
                       ["Cervical Mucus:Dry", "Cervical Mucus:Sticky", "Cervical Mucus:Creamy", "Cervical Mucus:Egg White"])
        XCTAssertTrue(TagFormLogic.historyTags(phase: nil, blocks: blocks).isEmpty)
    }

    func testTopCategoryFromArchive() {
        let blocks = [block(.luteal, tags: ["Mood:Calm, Mood:Happy", "Symptom:Cramps"])]
        XCTAssertEqual(TagFormLogic.topCategory(phase: .luteal, blocks: blocks), .mood)
        XCTAssertNil(TagFormLogic.topCategory(phase: .menstrual, blocks: blocks))
        XCTAssertNil(TagFormLogic.topCategory(phase: nil, blocks: blocks))
    }
}
