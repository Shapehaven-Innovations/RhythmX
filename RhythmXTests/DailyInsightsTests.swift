import XCTest
@testable import RhythmX

// MARK: - Fakes

private struct FakeGenerator: InsightTextGenerating {
    var isAvailable = true
    var result: Result<GeneratedInsightText, Error>
    var onCall: () -> Void = {}

    func generate(for facts: InsightFacts) async throws -> GeneratedInsightText {
        onCall()
        return try result.get()
    }
}

private struct FakeError: Error {}

private final class CountingWriter: InsightWriting {
    var isModelAvailable: Bool
    var calls = 0
    init(available: Bool = false) { isModelAvailable = available }

    func insights(for facts: InsightFacts) async -> DailyInsights {
        calls += 1
        return TemplateInsightWriter().insights(for: facts)
    }
}

final class DailyInsightsTests: XCTestCase {

    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: today.startOfDay)! }

    private let forbiddenInCopy = ["goddess", "\u{2014}", "\u{2013}", "diagnos", "birth control", "safe day", "cure"]

    private func cycleFacts(phase: Event.EventType? = .luteal, pattern: Bool = true) -> InsightFacts {
        InsightFacts(mode: .cycle, phase: phase, cycleDay: phase == nil ? nil : 24, daysUntilPeriod: phase == nil ? nil : 4,
                     recentTags: [.init(label: "Cramps", count: 3), .init(label: "Bloating", count: 2)],
                     tagsLoggedToday: 0,
                     pattern: pattern ? .init(label: "Sweet Craving",
                                              sentence: "Sweet Craving came up on days 24 to 27, in your luteal phase, in 4 of your last 5 cycles.") : nil)
    }

    // MARK: - Template writer

    func testLutealMoodLine() {
        let insights = TemplateInsightWriter().insights(for: cycleFacts())
        XCTAssertEqual(insights.moodLine, "Turn inward. Energy may soften before your period. Go gently.")
        XCTAssertFalse(insights.moodLineIsAI)
    }

    func testEveryPhaseHasItsOwnMoodLine() {
        let lines = Event.EventType.allCases.map { TemplateInsightWriter().insights(for: cycleFacts(phase: $0)).moodLine }
        XCTAssertEqual(Set(lines).count, 4)
    }

    func testCycleTilesInOrder() {
        let kinds = TemplateInsightWriter().insights(for: cycleFacts()).tiles.map(\.kind)
        XCTAssertEqual(kinds, [.logPrompt, .cycleDay, .possibleToday, .pattern, .energy])
    }

    func testFirstTileIsAlwaysTheLogPrompt() {
        for mode in TrackingMode.allCases {
            let facts = InsightFacts(mode: mode)
            XCTAssertEqual(TemplateInsightWriter().insights(for: facts).tiles.first?.kind, .logPrompt, mode.rawValue)
        }
    }

    func testCycleWithoutDataShowsOnlyTheLogPrompt() {
        let insights = TemplateInsightWriter().insights(for: InsightFacts(mode: .cycle))
        XCTAssertEqual(insights.tiles.map(\.kind), [.logPrompt])
        XCTAssertFalse(insights.moodLine.isEmpty)
    }

    func testCycleDayTileReadsTheNumbers() throws {
        let tile = try XCTUnwrap(TemplateInsightWriter().insights(for: cycleFacts()).tiles.first { $0.kind == .cycleDay })
        XCTAssertEqual(tile.title, "Cycle day 24")
        XCTAssertTrue(tile.body.contains("4 days"), tile.body)
    }

    func testPlanningFertileTileAlwaysEndsWithTheEstimateLine() {
        for level in InsightFacts.FertileLevel.allCases {
            let facts = InsightFacts(mode: .planning, phase: .follicular, cycleDay: 10, daysUntilPeriod: 18, fertileLevel: level)
            let insights = TemplateInsightWriter().insights(for: facts)
            let tile = insights.tiles.first { $0.kind == .fertile }
            XCTAssertNotNil(tile, "\(level)")
            XCTAssertTrue(tile?.body.hasSuffix("Estimates only.") ?? false, tile?.body ?? "")
            for text in [tile?.title ?? "", tile?.body ?? ""] {
                for word in ["birth control", "safe", "protected", "contracept"] {
                    XCTAssertFalse(text.lowercased().contains(word), "\(level): \(text)")
                }
            }
        }
    }

    func testPlanningTilesInOrder() {
        let facts = InsightFacts(mode: .planning, phase: .ovulation, cycleDay: 14, daysUntilPeriod: 14, fertileLevel: .peak,
                                 pattern: .init(label: "Egg White", sentence: "Egg White came up on day 13, in your ovulation phase, in 3 of your last 3 cycles."))
        XCTAssertEqual(TemplateInsightWriter().insights(for: facts).tiles.map(\.kind), [.logPrompt, .cycleDay, .fertile, .pattern, .energy])
    }

    func testMenopauseTilesAndNoCycleTiles() {
        let facts = InsightFacts(mode: .menopause, recentTags: [.init(label: "Hot Flashes", count: 9)], tagsLoggedToday: 2,
                                 pattern: .init(label: "Brain Fog", sentence: "Brain Fog came up 6 times in 4 of the last 8 weeks."),
                                 monthsSinceLastPeriod: 7, hotFlashesThisWeek: 9, hotFlashesLastWeek: 14, sleepAverageHours: 6.7)
        let insights = TemplateInsightWriter().insights(for: facts)
        XCTAssertEqual(insights.tiles.map(\.kind), [.logPrompt, .menopauseSymptoms, .sleep, .pattern])
        let hot = insights.tiles.first { $0.kind == .menopauseSymptoms }
        XCTAssertEqual(hot?.body, "9 this week, 14 last week.")
        XCTAssertTrue(insights.tiles.first { $0.kind == .sleep }?.body.contains("Apple Health") ?? false)
    }

    func testTemplateCopyIsPlainEverywhere() {
        var all: [InsightFacts] = []
        for phase in [nil] + Event.EventType.allCases.map(Optional.some) {
            all.append(cycleFacts(phase: phase))
            for level in InsightFacts.FertileLevel.allCases {
                all.append(InsightFacts(mode: .planning, phase: phase, cycleDay: phase == nil ? nil : 3,
                                        daysUntilPeriod: phase == nil ? nil : 0, periodLateDays: nil, fertileLevel: level, tagsLoggedToday: 1))
            }
        }
        all.append(InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 31, periodLateDays: 3))
        all.append(InsightFacts(mode: .menopause, hotFlashesThisWeek: 0, hotFlashesLastWeek: 0))
        for facts in all {
            let insights = TemplateInsightWriter().insights(for: facts)
            let texts = [insights.moodLine, insights.notificationTitle, insights.notificationBody]
                + insights.tiles.flatMap { [$0.title, $0.body] }
            for text in texts {
                XCTAssertEqual(TagFormLogic.removingEmoji(text), text, "no emoji: \(text)")
                for word in forbiddenInCopy {
                    XCTAssertFalse(text.lowercased().contains(word), "\(word) in \(text)")
                }
            }
            XCTAssertFalse(insights.tiles.contains { $0.isAI })
            XCTAssertFalse(insights.notificationTitle.isEmpty)
            XCTAssertFalse(insights.notificationBody.isEmpty)
        }
    }

    // MARK: - Validator

    private func validText() -> GeneratedInsightText {
        GeneratedInsightText(moodLine: "A slower day. Let your energy set the pace.",
                             energy: "Energy may dip a little. Short walks and early nights can help.",
                             pattern: "Sweet Craving tends to show up late in your cycle, in 4 of your last 5 cycles.")
    }

    func testValidatorAcceptsPlainTextNamingKnownTags() {
        XCTAssertTrue(InsightTextValidator.isValid(validText(), for: cycleFacts()))
    }

    func testValidatorRejectsAnInventedTag() {
        var text = validText()
        text.pattern = "Headache tends to show up late in your cycle."
        XCTAssertFalse(InsightTextValidator.isValid(text, for: cycleFacts()))
    }

    func testValidatorRejectsForbiddenWords() {
        for bad in ["This could be a diagnosis worth checking.", "Hello goddess, rest today.",
                    "Use this as birth control.", "These are safe days.", "Ask your doctor about a cure.",
                    "Rest today \u{2014} you earned it.", "Rest today \u{1F319}"] {
            var text = validText()
            text.moodLine = bad
            XCTAssertFalse(InsightTextValidator.isValid(text, for: cycleFacts()), bad)
        }
    }

    func testValidatorRejectsTooLongEmptyOrInventedNumbers() {
        var long = validText()
        long.moodLine = String(repeating: "Rest well. ", count: 20)
        XCTAssertFalse(InsightTextValidator.isValid(long, for: cycleFacts()))
        var empty = validText()
        empty.moodLine = "  "
        XCTAssertFalse(InsightTextValidator.isValid(empty, for: cycleFacts()))
        var number = validText()
        number.energy = "Energy dips on day 9."
        XCTAssertFalse(InsightTextValidator.isValid(number, for: cycleFacts()))
    }

    func testValidatorRejectsSpelledOutNumbers() {
        for bad in ["Cramps came up three times this week.", "Energy dips for a couple of days.",
                    "You logged Bloating twice.", "Rest once more today.", "Day twenty is close.",
                    "Forty days of logs.", "Zero days to go.", "Eleven tags so far."] {
            var text = validText()
            text.moodLine = bad
            XCTAssertFalse(InsightTextValidator.isValid(text, for: cycleFacts()), bad)
        }
    }

    func testValidatorRejectsOvulationAndPeriodTimingClaims() {
        for bad in ["You may ovulate soon.", "Ovulation is near.", "Your period starts soon.",
                    "Your period is late.", "Your period is coming.", "Your period is due."] {
            var text = validText()
            text.moodLine = bad
            XCTAssertFalse(InsightTextValidator.isValid(text, for: cycleFacts()), bad)
        }
    }

    func testValidatorAllowsThePhaseNameItWasGiven() {
        let facts = InsightFacts(mode: .cycle, phase: .ovulation, cycleDay: 14)
        let text = GeneratedInsightText(moodLine: "Full bloom in your ovulation phase.", energy: "Energy is high in this phase.", pattern: nil)
        XCTAssertTrue(InsightTextValidator.isValid(text, for: facts))
        var claim = text
        claim.moodLine = "You will ovulate today."
        XCTAssertFalse(InsightTextValidator.isValid(claim, for: facts))
    }

    func testValidatorRejectsEveryDashAndMarkup() {
        for bad in ["Rest today -- you earned it.", "Rest\u{2010}day.", "Rest\u{2011}day.", "Rest today \u{2012} now.",
                    "Rest today \u{2015} now.", "Rest today \u{2212} now.", "Rest today \u{2013} now.",
                    "**Rest** today.", "# Rest today", "Rest today \u{2022} now.", "Rest today ~ now."] {
            var text = validText()
            text.moodLine = bad
            XCTAssertFalse(InsightTextValidator.isValid(text, for: cycleFacts()), bad)
        }
    }

    func testValidatorRejectsAMissingPatternWhenOneIsExpected() {
        var text = validText()
        text.pattern = nil
        XCTAssertFalse(InsightTextValidator.isValid(text, for: cycleFacts()))
    }

    // MARK: - Foundation Models writer (with a fake generator)

    func testOnDeviceTextIsUsedAndMarked() async {
        let writer = FoundationModelsInsightWriter(generator: FakeGenerator(result: .success(validText())))
        let insights = await writer.insights(for: cycleFacts())
        XCTAssertEqual(insights.moodLine, validText().moodLine)
        XCTAssertTrue(insights.moodLineIsAI)
        XCTAssertEqual(insights.tiles.first { $0.kind == .pattern }?.body, validText().pattern)
        XCTAssertEqual(insights.tiles.first { $0.kind == .pattern }?.isAI, true)
        XCTAssertEqual(insights.tiles.first { $0.kind == .energy }?.isAI, true)
        XCTAssertEqual(insights.tiles.first { $0.kind == .cycleDay }?.isAI, false, "numbers stay with the template")
        XCTAssertEqual(insights.tiles.first { $0.kind == .logPrompt }?.isAI, false)
        XCTAssertEqual(insights.notificationBody, validText().moodLine)
    }

    func testInvalidOutputFallsBackToTheTemplate() async {
        var text = validText()
        text.pattern = "Headache tends to show up late in your cycle."
        let writer = FoundationModelsInsightWriter(generator: FakeGenerator(result: .success(text)))
        let insights = await writer.insights(for: cycleFacts())
        XCTAssertEqual(insights, TemplateInsightWriter().insights(for: cycleFacts()))
    }

    func testGeneratorErrorFallsBackToTheTemplate() async {
        let writer = FoundationModelsInsightWriter(generator: FakeGenerator(result: .failure(FakeError())))
        let insights = await writer.insights(for: cycleFacts())
        XCTAssertEqual(insights, TemplateInsightWriter().insights(for: cycleFacts()))
    }

    func testUnavailableModelIsNeverCalled() async {
        var called = false
        let generator = FakeGenerator(isAvailable: false, result: .success(validText()), onCall: { called = true })
        let writer = FoundationModelsInsightWriter(generator: generator)
        XCTAssertFalse(writer.isModelAvailable)
        let insights = await writer.insights(for: cycleFacts())
        XCTAssertFalse(called)
        XCTAssertEqual(insights, TemplateInsightWriter().insights(for: cycleFacts()))
    }

    func testPlanningFertileTileStaysTemplateWithItsEstimateLine() async {
        let facts = InsightFacts(mode: .planning, phase: .follicular, cycleDay: 10, daysUntilPeriod: 18, fertileLevel: .high,
                                 recentTags: [.init(label: "Egg White", count: 2)])
        let text = GeneratedInsightText(moodLine: "Energy is building. A good day to plan.", energy: "Energy is building.", pattern: nil)
        let insights = await FoundationModelsInsightWriter(generator: FakeGenerator(result: .success(text))).insights(for: facts)
        let fertile = insights.tiles.first { $0.kind == .fertile }
        XCTAssertEqual(fertile?.isAI, false)
        XCTAssertTrue(fertile?.body.hasSuffix("Estimates only.") ?? false)
    }

    func testPromptIsBuiltFromFactsOnly() {
        var events = CycleGenerator.events(startDate: day(-23))
        if let i = events.firstIndex(where: { $0.date.startOfDay == day(-1) }) {
            events[i].note = "Private note about Alex"
            events[i].tags = "Symptom:Cramps, Other:Talked to Alex, Medication:Birth Control"
        }
        let facts = InsightFacts.make(events: events, archivedBlocks: [], mode: .cycle, today: today)
        let prompt = FoundationModelsInsightWriter.prompt(for: facts)
        XCTAssertTrue(prompt.contains("Cramps"))
        for leaked in ["Alex", "Private", "Birth Control", "Symptom:", "2026", "Oct"] {
            XCTAssertFalse(prompt.contains(leaked), leaked)
        }
        XCTAssertLessThan(prompt.count, 1_200, "a small prompt leaves room in the 4,096 token context")
    }

    // MARK: - Facts

    func testCycleFactsExcludeMenopauseEvents() {
        let cycle = CycleGenerator.events(startDate: day(-23)).map { event -> Event in
            var e = event
            if e.date.startOfDay == day(0) { e.tags = "Symptom:Bloating" }
            return e
        }
        let menopause = [Event(eventType: .follicular, date: day(0), note: "", tags: "Menopause:Hot Flashes, Menopause:Hot Flashes",
                               mode: .menopause)]
        let withMenopause = InsightFacts.make(events: cycle + menopause, archivedBlocks: [], mode: .cycle, today: today)
        let without = InsightFacts.make(events: cycle, archivedBlocks: [], mode: .cycle, today: today)
        XCTAssertEqual(withMenopause, without, "menopause entries change nothing in cycle facts")
        XCTAssertEqual(withMenopause.recentTags.map(\.label), ["Bloating"])
        XCTAssertNil(withMenopause.hotFlashesThisWeek)
        XCTAssertNil(withMenopause.monthsSinceLastPeriod)
        XCTAssertNotNil(withMenopause.phase)
        XCTAssertNotNil(withMenopause.cycleDay)
        XCTAssertNil(withMenopause.fertileLevel, "fertility is a Planning fact")
    }

    func testMenopauseFactsCarryNoCycleData() {
        let cycle = CycleGenerator.events(startDate: day(-23)).map { event -> Event in
            var e = event
            if e.date.startOfDay == day(0) { e.tags = "Symptom:Bloating" }
            return e
        }
        let menopause = [Event(eventType: .follicular, date: day(0), note: "", tags: "Menopause:Hot Flashes, Menopause:Hot Flashes",
                               mode: .menopause),
                         Event(eventType: .follicular, date: day(-8), note: "", tags: "Menopause:Hot Flashes", mode: .menopause)]
        let facts = InsightFacts.make(events: cycle + menopause, archivedBlocks: [], mode: .menopause, today: today)
        XCTAssertNil(facts.phase)
        XCTAssertNil(facts.cycleDay)
        XCTAssertNil(facts.daysUntilPeriod)
        XCTAssertNil(facts.fertileLevel)
        XCTAssertEqual(facts.recentTags.map(\.label), ["Hot Flashes"])
        XCTAssertEqual(facts.recentTags.first?.count, 3)
        XCTAssertEqual(facts.hotFlashesThisWeek, 2)
        XCTAssertEqual(facts.hotFlashesLastWeek, 1)
        XCTAssertEqual(facts.tagsLoggedToday, 2)
        XCTAssertNotNil(facts.monthsSinceLastPeriod)
    }

    func testPlanningFactsHaveAFertileLevel() {
        let facts = InsightFacts.make(events: CycleGenerator.events(startDate: day(-12)), archivedBlocks: [], mode: .planning, today: today)
        XCTAssertNotNil(facts.fertileLevel)
    }

    func testFactsNeverHoldDatesNotesOrCustomText() throws {
        var events = CycleGenerator.events(startDate: day(-23))
        for i in events.indices where events[i].date.startOfDay >= day(-3) && events[i].date.startOfDay <= day(0) {
            events[i].note = "secret"
            events[i].tags = "Other:My custom thing, Mood:Calm"
        }
        let facts = InsightFacts.make(events: events, archivedBlocks: [], mode: .cycle, today: today)
        let json = String(decoding: try JSONEncoder().encode(facts), as: UTF8.self)
        XCTAssertFalse(json.contains("secret"))
        XCTAssertFalse(json.contains("custom"))
        XCTAssertFalse(json.contains("Mood:"))
        XCTAssertEqual(facts.recentTags.map(\.label), ["Calm"])
    }

    // MARK: - Service and cache

    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testCacheHitForSameDayModeAndFacts() async {
        let writer = CountingWriter()
        let service = DailyInsightsService(writer: writer, defaults: freshDefaults("DailyInsightsTests.hit"),
                                           now: { self.today }, osVersion: "26.5")
        let a = await service.insights(for: cycleFacts())
        let b = await service.insights(for: cycleFacts())
        XCTAssertEqual(writer.calls, 1)
        XCTAssertEqual(a, b)
    }

    func testCacheSurvivesANewServiceInstance() async {
        let defaults = freshDefaults("DailyInsightsTests.persist")
        let first = CountingWriter()
        _ = await DailyInsightsService(writer: first, defaults: defaults, now: { self.today }, osVersion: "26.5").insights(for: cycleFacts())
        let second = CountingWriter()
        _ = await DailyInsightsService(writer: second, defaults: defaults, now: { self.today }, osVersion: "26.5").insights(for: cycleFacts())
        XCTAssertEqual(second.calls, 0)
    }

    func testCacheMissWhenFactsChange() async {
        let writer = CountingWriter()
        let service = DailyInsightsService(writer: writer, defaults: freshDefaults("DailyInsightsTests.facts"),
                                           now: { self.today }, osVersion: "26.5")
        _ = await service.insights(for: cycleFacts())
        _ = await service.insights(for: cycleFacts(pattern: false))
        XCTAssertEqual(writer.calls, 2)
    }

    func testCacheMissOnANewDay() async {
        let writer = CountingWriter()
        var now = today
        let service = DailyInsightsService(writer: writer, defaults: freshDefaults("DailyInsightsTests.day"),
                                           now: { now }, osVersion: "26.5")
        _ = await service.insights(for: cycleFacts())
        now = day(1)
        _ = await service.insights(for: cycleFacts())
        XCTAssertEqual(writer.calls, 2)
    }

    func testCacheMissWhenOSOrModelAvailabilityChanges() async {
        let defaults = freshDefaults("DailyInsightsTests.os")
        let writer = CountingWriter()
        _ = await DailyInsightsService(writer: writer, defaults: defaults, now: { self.today }, osVersion: "26.5").insights(for: cycleFacts())
        _ = await DailyInsightsService(writer: writer, defaults: defaults, now: { self.today }, osVersion: "26.6").insights(for: cycleFacts())
        XCTAssertEqual(writer.calls, 2)
        writer.isModelAvailable = true
        _ = await DailyInsightsService(writer: writer, defaults: defaults, now: { self.today }, osVersion: "26.6").insights(for: cycleFacts())
        XCTAssertEqual(writer.calls, 3)
    }

    func testCacheKeyHoldsDateModeOSAndAvailability() {
        let service = DailyInsightsService(writer: CountingWriter(available: true), defaults: freshDefaults("DailyInsightsTests.key"),
                                           now: { self.today }, osVersion: "26.5")
        XCTAssertEqual(service.cacheKey(for: cycleFacts()), "2026-10-20|cycle|26.5|ai")
    }

    func testServiceBuildsFactsFromStoresWithTheInjectedClock() async {
        let writer = CountingWriter()
        let service = DailyInsightsService(writer: writer, defaults: freshDefaults("DailyInsightsTests.make"),
                                           now: { self.today }, osVersion: "26.5")
        let insights = await service.insights(events: CycleGenerator.events(startDate: day(-23)), archivedBlocks: [], mode: .cycle)
        XCTAssertTrue(insights.tiles.contains { $0.kind == .cycleDay })
        XCTAssertEqual(writer.calls, 1)
    }
}
