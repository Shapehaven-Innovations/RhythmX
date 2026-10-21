import XCTest
@testable import RhythmX

/// Which insight cards Share offers per mode and what each one says. Cards are built only from the day's
/// insight tiles and facts: never tags, notes or dates; fertility cards always carry the estimate line.
final class ShareCardModelTests: XCTestCase {

    private let writer = TemplateInsightWriter()

    private func input(_ facts: InsightFacts, fertileToday: Bool = false, fertileStartsIn: Int? = nil,
                       name: String = "") -> ShareCardInput {
        ShareCardInput(mode: facts.mode, insights: writer.insights(for: facts), facts: facts,
                       fertileToday: fertileToday, fertileStartsIn: fertileStartsIn, sharerName: name)
    }

    private var cycleFacts: InsightFacts {
        InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 26, daysUntilPeriod: 3,
                     recentTags: [.init(label: "Headache", count: 4), .init(label: "Anxious", count: 2)],
                     tagsLoggedToday: 2,
                     pattern: .init(label: "Headache", sentence: "Headache shows up before your period, in 3 of 4 cycles."))
    }

    private var planningFacts: InsightFacts {
        InsightFacts(mode: .planning, phase: .follicular, cycleDay: 6, daysUntilPeriod: 22, fertileLevel: .rising)
    }

    private var menopauseFacts: InsightFacts {
        InsightFacts(mode: .menopause, recentTags: [.init(label: "Hot Flashes", count: 9)],
                     monthsSinceLastPeriod: 4, hotFlashesThisWeek: 6, hotFlashesLastWeek: 9, sleepAverageHours: 6.7)
    }

    private func allText(_ card: ShareCard) -> String {
        ([card.pickerTitle, card.pickerSummary, card.eyebrow, card.big ?? "", card.bigSide ?? "", card.bigSideDetail ?? "",
          card.subtitle ?? "", card.detail ?? "", card.estimateLine ?? "", card.disclaimer ?? "", card.footer,
          card.sharerLine ?? "", card.accessibilityDescription]
         + card.items.map(\.label) + card.facts.flatMap { [$0.lead, $0.rest] }).joined(separator: " | ")
    }

    // MARK: - Which cards

    func testCycleOffersDayPossiblePhaseCombinedAndMinimal() {
        let kinds = ShareCardModel.cards(for: input(cycleFacts)).map(\.kind)
        XCTAssertEqual(kinds, [.cycleDay, .possibleToday, .phase, .combined, .minimal])
    }

    func testPlanningOffersBestChancesWithTheEstimateLine() {
        let cards = ShareCardModel.cards(for: input(planningFacts, fertileStartsIn: 4))
        XCTAssertEqual(cards.map(\.kind), [.cycleDay, .phase, .bestChances, .combined, .minimal])
        let best = cards.first { $0.kind == .bestChances }!
        XCTAssertEqual(best.big, "4")
        XCTAssertEqual(best.bigSide, "days")
        XCTAssertEqual(best.estimateLine, TemplateInsightWriter.estimateLine)
        XCTAssertEqual(best.disclaimer, PlanningInsightsView.disclaimer)
        XCTAssertTrue(best.accessibilityDescription.contains("Estimates only."))
        // The combined cards repeat the estimate line next to the fertility line.
        for card in cards where card.kind == .combined || card.kind == .minimal {
            XCTAssertEqual(card.estimateLine, TemplateInsightWriter.estimateLine)
            XCTAssertTrue(card.facts.contains { $0.lead == "Best chances" })
        }
    }

    func testPlanningInsideTheWindowSaysNow() {
        let facts = InsightFacts(mode: .planning, phase: .ovulation, cycleDay: 14, daysUntilPeriod: 14, fertileLevel: .high)
        let best = ShareCardModel.cards(for: input(facts, fertileToday: true)).first { $0.kind == .bestChances }
        XCTAssertEqual(best?.big, "Now")
        XCTAssertNil(best?.bigSide)
        XCTAssertEqual(best?.estimateLine, TemplateInsightWriter.estimateLine)
    }

    func testPlanningWithoutAnUpcomingWindowHasNoBestChancesCard() {
        let kinds = ShareCardModel.cards(for: input(planningFacts)).map(\.kind)
        XCTAssertFalse(kinds.contains(.bestChances))
    }

    func testOnlyPlanningShowsBestChances() {
        let kinds = ShareCardModel.cards(for: input(cycleFacts, fertileToday: true, fertileStartsIn: 3)).map(\.kind)
        XCTAssertFalse(kinds.contains(.bestChances))
        for card in ShareCardModel.cards(for: input(cycleFacts, fertileStartsIn: 3)) {
            XCTAssertFalse(allText(card).contains("Best chances"), card.id)
        }
    }

    func testMenopauseNeverShowsFertilityOrCycleCards() {
        let cards = ShareCardModel.cards(for: input(menopauseFacts, fertileToday: true, fertileStartsIn: 2))
        XCTAssertEqual(cards.map(\.kind), [.hotFlashes, .combined, .minimal])
        for card in cards {
            let text = allText(card).lowercased()
            for banned in ["fertile", "ovulation", "best chances", "estimates only", "birth control", "cycle day", "period in"] {
                XCTAssertFalse(text.contains(banned), "\(card.id) says \(banned)")
            }
            XCTAssertNil(card.phase)
        }
        let hot = cards[0]
        XCTAssertEqual(hot.big, "6")
        XCTAssertEqual(hot.detail, "9 last week.")
    }

    func testNoCycleMeansNothingToShareInCycleAndPlanning() {
        XCTAssertTrue(ShareCardModel.cards(for: input(InsightFacts(mode: .cycle))).isEmpty)
        XCTAssertTrue(ShareCardModel.cards(for: input(InsightFacts(mode: .planning))).isEmpty)
    }

    // MARK: - Text per card

    func testCycleDayCard() {
        let card = ShareCardModel.cards(for: input(cycleFacts))[0]
        XCTAssertEqual(card.eyebrow, "Cycle day")
        XCTAssertEqual(card.big, "26")
        XCTAssertEqual(card.subtitle, "Luteal phase")
        XCTAssertEqual(card.detail, "Period in about 3 days")
        XCTAssertEqual(card.pickerSummary, "Day 26, period in about 3 days")
        XCTAssertEqual(card.style, .moon)
        XCTAssertEqual(card.phase, .luteal)
    }

    func testPeriodLineFollowsTheEstimate() {
        func detail(_ facts: InsightFacts) -> String? { ShareCardModel.cards(for: input(facts))[0].detail }
        XCTAssertEqual(detail(InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 28, daysUntilPeriod: 0)), "Period may start today")
        XCTAssertEqual(detail(InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 27, daysUntilPeriod: 1)), "Period may start tomorrow")
        XCTAssertEqual(detail(InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 31, periodLateDays: 2)),
                       "Period 2 days later than estimated")
        XCTAssertEqual(detail(InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 30, periodLateDays: 1)),
                       "Period 1 day later than estimated")
        XCTAssertNil(detail(InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 30)))
    }

    func testPossibleTodayListsThePhaseSymptomsFromTheTile() {
        let card = ShareCardModel.cards(for: input(cycleFacts))[1]
        XCTAssertEqual(card.eyebrow, "Possible today")
        let expected = Array((TagFormLogic.phaseSymptomSuggestions[.luteal] ?? []).prefix(3))
        XCTAssertEqual(card.items.map(\.label), expected)
        let tile = writer.insights(for: cycleFacts).tile(.possibleToday)!
        XCTAssertEqual(card.items.map(\.symbol), tile.symbols)
        XCTAssertEqual(card.pickerSummary, "Mood swings, breast tenderness, food cravings")
    }

    func testPhaseCardUsesThePhaseLineNeverTheWrittenOne() {
        var insights = writer.insights(for: cycleFacts)
        insights.moodLine = "Headache often shows up for you now."
        insights.moodLineIsAI = true
        let input = ShareCardInput(mode: .cycle, insights: insights, facts: cycleFacts, fertileToday: false,
                                   fertileStartsIn: nil, sharerName: "")
        let card = ShareCardModel.cards(for: input).first { $0.kind == .phase }!
        XCTAssertEqual(card.eyebrow, "Phase 4 of 4")
        XCTAssertEqual(card.big, "Turn inward")
        XCTAssertEqual(card.detail, "Luteal phase. Energy may soften before your period. Go gently.")
        XCTAssertEqual(card.pickerSummary, "Luteal, turn inward")
    }

    func testCombinedCard() {
        let card = ShareCardModel.cards(for: input(cycleFacts)).first { $0.kind == .combined }!
        XCTAssertEqual(card.style, .aura)
        XCTAssertEqual(card.eyebrow, "My cycle today")
        XCTAssertEqual(card.big, "26")
        XCTAssertEqual(card.bigSide, "Luteal")
        XCTAssertEqual(card.bigSideDetail, "Turn inward")
        XCTAssertEqual(card.facts.map(\.lead), ["Period", "Possible today"])
        XCTAssertEqual(card.facts.map(\.rest), ["in about 3 days", "mood swings, breast tenderness, food cravings"])
        XCTAssertEqual(card.disclaimer, PlanningInsightsView.disclaimer)
        let minimal = ShareCardModel.cards(for: input(cycleFacts)).first { $0.kind == .minimal }!
        XCTAssertEqual(minimal.style, .minimal)
        XCTAssertEqual(minimal.facts, card.facts)
    }

    // MARK: - Privacy

    func testCardsNeverCarryTagsNotesOrDates() {
        let months = Calendar(identifier: .gregorian).monthSymbols + Calendar(identifier: .gregorian).shortMonthSymbols
        for facts in [cycleFacts, planningFacts, menopauseFacts] {
            for card in ShareCardModel.cards(for: input(facts, fertileStartsIn: 4)) {
                let text = allText(card)
                XCTAssertFalse(text.contains("Headache"), card.id)
                XCTAssertFalse(text.contains("Anxious"), card.id)
                XCTAssertFalse(text.contains("Hot Flashes"), card.id)   // the tag label; the card says "hot flashes"
                for month in months { XCTAssertFalse(text.contains(month + " "), "\(card.id) names \(month)") }
                XCTAssertNil(text.range(of: #"\d{1,2}/\d{1,2}"#, options: .regularExpression), card.id)
            }
        }
    }

    func testCopyIsPlain() {
        for facts in [cycleFacts, planningFacts, menopauseFacts] {
            for card in ShareCardModel.cards(for: input(facts, fertileStartsIn: 4, name: "Ana")) {
                let text = allText(card)
                XCTAssertFalse(text.contains("\u{2014}"), card.id)
                XCTAssertFalse(text.lowercased().contains("goddess"), card.id)
                XCTAssertFalse(text.unicodeScalars.contains { $0.properties.isEmojiPresentation }, card.id)
            }
        }
    }

    // MARK: - Footer, name, accessibility, files

    func testFooterAndOptionalName() {
        let plain = ShareCardModel.cards(for: input(cycleFacts))[0]
        XCTAssertEqual(plain.footer, "Shared from RhythmX")
        XCTAssertNil(plain.sharerLine)
        let named = ShareCardModel.cards(for: input(cycleFacts, name: "  Ana  "))[0]
        XCTAssertEqual(named.sharerLine, "From Ana")
        let long = ShareCardModel.cards(for: input(cycleFacts, name: String(repeating: "A", count: 60)))[0]
        XCTAssertEqual(long.sharerLine?.count, "From ".count + ShareCardModel.maxNameLength)
    }

    func testAccessibilityDescriptionReadsTheWholeCard() {
        let card = ShareCardModel.cards(for: input(cycleFacts, name: "Ana"))[0]
        XCTAssertEqual(card.accessibilityDescription,
                       "Cycle day card. Cycle day 26. Luteal phase. Period in about 3 days. From Ana. Shared from RhythmX.")
    }

    func testFileNamesAreUniquePNGs() {
        let cards = ShareCardModel.cards(for: input(planningFacts, fertileStartsIn: 4))
            + ShareCardModel.cards(for: input(cycleFacts)) + ShareCardModel.cards(for: input(menopauseFacts))
        let names = Set(cards.map(\.fileName))
        XCTAssertEqual(names.count, Set(cards.map(\.kind)).count)
        for card in cards {
            XCTAssertTrue(card.fileName.hasPrefix("RhythmX-"))
            XCTAssertTrue(card.fileName.hasSuffix(".png"))
            XCTAssertFalse(card.fileName.contains(" "))
        }
        XCTAssertEqual(ShareCardModel.cards(for: input(cycleFacts))[0].fileName, "RhythmX-cycle-day.png")
    }

    func testDefaultSelectionIsTheSingleCards() {
        XCTAssertEqual(ShareCardModel.defaultSelection(ShareCardModel.cards(for: input(cycleFacts))),
                       [.cycleDay, .possibleToday, .phase])
        XCTAssertEqual(ShareCardModel.defaultSelection(ShareCardModel.cards(for: input(menopauseFacts))), [.hotFlashes])
    }

    func testShareButtonTitle() {
        XCTAssertEqual(ShareCardModel.shareButtonTitle(count: 0), "Share")
        XCTAssertEqual(ShareCardModel.shareButtonTitle(count: 1), "Share Card")
        XCTAssertEqual(ShareCardModel.shareButtonTitle(count: 3), "Share 3 Cards")
    }

    func testRenderSizeIsFourByFive() {
        XCTAssertEqual(ShareCardModel.pixelSize, CGSize(width: 1080, height: 1350))
        XCTAssertEqual(ShareCardModel.pointSize.width * ShareCardModel.renderScale, 1080)
        XCTAssertEqual(ShareCardModel.pointSize.height * ShareCardModel.renderScale, 1350)
    }

    // MARK: - Rendering on demand

    @MainActor
    func testImagesAreRenderedOnlyWhenAskedAndCachedPerCardThemeAndName() throws {
        let cache = ShareCardRenderCache()
        let card = try XCTUnwrap(ShareCardModel.cards(for: input(cycleFacts)).first)
        let palette = AppTheme.blush.light
        let item = ShareCardItem(card: card, palette: palette, isDark: false, themeID: "blush", name: "", cache: cache)
        XCTAssertEqual(cache.renderCount, 0, "building the share list renders nothing")

        let first = try XCTUnwrap(item.renderNow())
        XCTAssertEqual(cache.renderCount, 1)
        XCTAssertEqual(item.renderNow(), first)
        XCTAssertEqual(cache.renderCount, 1, "a second ask uses the cached image")

        let named = ShareCardItem(card: card, palette: palette, isDark: false, themeID: "blush", name: "Sam", cache: cache)
        _ = named.renderNow()
        let dark = ShareCardItem(card: card, palette: AppTheme.blush.dark, isDark: true, themeID: "blush", name: "", cache: cache)
        _ = dark.renderNow()
        let other = ShareCardItem(card: card, palette: AppTheme.eclipse.light, isDark: false, themeID: "eclipse", name: "", cache: cache)
        _ = other.renderNow()
        XCTAssertEqual(cache.renderCount, 4, "name, dark mode and theme each make their own image")
    }
}
