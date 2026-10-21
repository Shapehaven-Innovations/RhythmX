import XCTest
@testable import RhythmX

/// The quick log card that a Daily insights tap opens: which round choices it offers, the question it asks,
/// the selection with "None of these", and what one tap on the log button writes.
@MainActor
final class QuickLogCardLogicTests: XCTestCase {
    private let calendar = Calendar.current
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 20))!
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }
    private func pick(_ c: TagCategory, _ v: String) -> TagPick { TagPick(category: c, value: v) }

    // MARK: - Choices

    func testChoicesPreferHerOwnPhaseHistoryThenFrequentTagsThenPhaseSuggestions() {
        let events = [
            Event(eventType: .luteal, date: day(-30), note: "", tags: "Symptom:Headache, Dietary:Sweet Craving"),
            Event(eventType: .luteal, date: day(-29), note: "", tags: "Symptom:Headache"),
            Event(eventType: .menstrual, date: day(-20), note: "", tags: "Symptom:Cramps, Symptom:Cramps2"),
        ]
        let choices = QuickLogCardLogic.choices(mode: .cycle, phase: .luteal, events: events,
                                                history: ["Symptom:Bloating"], today: now)
        XCTAssertEqual(choices.map(\.value), ["Bloating", "Headache", "Sweet Craving", "Cramps"])
    }

    func testChoicesFallBackToPhaseSuggestionsAndSkipWhatIsLoggedToday() {
        let events = [Event(eventType: .luteal, date: now, note: "", tags: "Symptom:Breast Tenderness")]
        let choices = QuickLogCardLogic.choices(mode: .cycle, phase: .luteal, events: events, history: [], today: now)
        XCTAssertEqual(choices.map(\.value), ["Mood Swings", "Food Cravings", "PMS", "Cramps"])
    }

    func testChoicesStayInTheModeAndLeaveOutTemperatures() {
        let events = [
            Event(eventType: .follicular, date: day(-1), note: "", tags: "Basal Temp:97.8, Planning:Intercourse", mode: .planning),
            Event(eventType: .follicular, date: day(-1), note: "", tags: "Menopause:Hot Flashes", mode: .menopause),
        ]
        let planning = QuickLogCardLogic.choices(mode: .planning, phase: .follicular, events: events, history: [], today: now)
        XCTAssertEqual(planning.first, pick(.planning, "Intercourse"))
        XCTAssertFalse(planning.contains { $0.category == .basalTemp })
        XCTAssertFalse(planning.contains { $0.category == .menopause })
        XCTAssertEqual(planning.count, 4)
    }

    func testMenopauseChoicesKeepRepeatableTagsEvenWhenLoggedToday() {
        let events = [Event(eventType: .follicular, date: now, note: "", tags: "Menopause:Hot Flashes", mode: .menopause)]
        let choices = QuickLogCardLogic.choices(mode: .menopause, phase: nil, events: events, history: [], today: now)
        XCTAssertEqual(choices.map(\.value), ["Hot Flashes", "Night Sweats", "Poor Sleep", "Brain Fog"])
    }

    // MARK: - Copy

    func testQuestionFollowsThePhase() {
        XCTAssertEqual(QuickLogCardLogic.question(mode: .cycle, phase: .luteal), "Anything from your luteal phase today?")
        XCTAssertEqual(QuickLogCardLogic.question(mode: .cycle, phase: nil), "Have you noticed anything today?")
        XCTAssertEqual(QuickLogCardLogic.question(mode: .menopause, phase: nil), "Have you noticed anything today?")
    }

    // MARK: - Selection

    func testPickingAndNoneOfTheseExcludeEachOther() {
        var selection = QuickLogSelection()
        XCTAssertFalse(selection.canApply)
        XCTAssertEqual(selection.buttonTitle, "Log")
        selection.toggle(pick(.symptom, "Bloating"))
        selection.toggle(pick(.dietary, "Sweet Craving"))
        XCTAssertEqual(selection.buttonTitle, "Log 2")
        selection.chooseNone()
        XCTAssertTrue(selection.noneChosen)
        XCTAssertTrue(selection.picks.isEmpty)
        XCTAssertEqual(selection.buttonTitle, "Done")
        XCTAssertTrue(selection.canApply)
        selection.toggle(pick(.symptom, "Bloating"))
        XCTAssertFalse(selection.noneChosen)
        selection.toggle(pick(.symptom, "Bloating"))
        XCTAssertFalse(selection.canApply)
    }

    func testOvulationTestResultsReplaceEachOther() {
        var selection = QuickLogSelection()
        selection.toggle(pick(.planning, "Ovulation Test Faint"))
        selection.toggle(pick(.planning, "Intercourse"))
        selection.toggle(pick(.planning, "Ovulation Test Positive"))
        XCTAssertEqual(selection.picks.map(\.value), ["Intercourse", "Ovulation Test Positive"])
    }

    func testLoggingUsesMediumWhereAStrengthApplies() {
        var selection = QuickLogSelection()
        selection.toggle(pick(.symptom, "Bloating"))
        selection.toggle(pick(.mood, "Calm"))
        XCTAssertEqual(selection.tagsToLog, [.init(raw: "Symptom:Bloating", intensity: .medium),
                                             .init(raw: "Mood:Calm", intensity: nil)])
        selection.chooseNone()
        XCTAssertTrue(selection.tagsToLog.isEmpty)
    }

    func testLoggedSummary() {
        XCTAssertEqual(QuickLogCardLogic.loggedTitle(cycleDay: 26), "Logged for day 26")
        XCTAssertEqual(QuickLogCardLogic.loggedTitle(cycleDay: nil), "Logged for today")
        XCTAssertEqual(QuickLogCardLogic.loggedDetail([pick(.symptom, "Bloating"), pick(.dietary, "Sweet Craving")]),
                       "Bloating, Sweet Craving. See you tomorrow.")
    }

    func testLogWritesThroughTheStoreWithTheDuplicateRules() {
        let store = EventStore(preview: true)
        store.events = CycleGenerator.events(startDate: day(-25), cycleLength: 28)
        var selection = QuickLogSelection()
        selection.toggle(pick(.symptom, "Bloating"))
        let logged = QuickLogCardLogic.log(selection, store: store, on: now, mode: .cycle)
        XCTAssertEqual(logged, [pick(.symptom, "Bloating")])
        let todayEvent = store.events.first { calendar.isDate($0.date, inSameDayAs: now) }
        XCTAssertEqual(todayEvent?.intensity(for: "Symptom:Bloating"), .medium)
        XCTAssertTrue(QuickLogCardLogic.log(selection, store: store, on: now, mode: .cycle).isEmpty)
    }
}
