import XCTest
@testable import RhythmX

final class OnboardingFlowTests: XCTestCase {

    func testFivePagesInOrder() {
        XCTAssertEqual(OnboardingPage.allCases, [.welcome, .mode, .lastPeriod, .phases, .makeItYours])
        XCTAssertEqual(OnboardingPage.welcome.next, .mode)
        XCTAssertNil(OnboardingPage.makeItYours.next)
        XCTAssertNil(OnboardingPage.welcome.previous)
        XCTAssertEqual(OnboardingPage.phases.previous, .lastPeriod)
    }

    func testEveryPageBeforeTheLastCanBeSkippedAndTheLastFinishes() {
        for page in OnboardingPage.allCases.dropLast() { XCTAssertTrue(page.showsSkip, "\(page)") }
        XCTAssertFalse(OnboardingPage.makeItYours.showsSkip)
        XCTAssertEqual(OnboardingPage.makeItYours.primaryTitle, "Start Tracking")
        XCTAssertEqual(OnboardingPage.mode.primaryTitle, "Continue")
    }

    func testBackIsOfferedAfterTheWelcome() {
        XCTAssertFalse(OnboardingPage.welcome.showsBack)
        for page in OnboardingPage.allCases.dropFirst() { XCTAssertTrue(page.showsBack) }
    }

    func testReplayCompletesWithTheSameLastPage() {
        XCTAssertEqual(OnboardingPage.makeItYours.primaryTitle(replay: true), "Done")
        XCTAssertEqual(OnboardingPage.makeItYours.primaryTitle(replay: false), "Start Tracking")
    }

    func testDotsAreOnePerPage() {
        XCTAssertEqual(OnboardingPage.lastPeriod.index, 2)
        XCTAssertEqual(OnboardingPage.count, 5)
        XCTAssertEqual(OnboardingPage.lastPeriod.accessibilityPosition, "Page 3 of 5")
    }

    func testCopyHasNoDashesOrEmoji() {
        for page in OnboardingPage.allCases {
            for text in [page.title, page.body ?? ""] {
                XCTAssertFalse(text.contains("\u{2014}"), text)
                XCTAssertFalse(text.contains("\u{2013}"), text)
                XCTAssertEqual(TagFormLogic.removingEmoji(text), text)
                XCTAssertFalse(text.lowercased().contains("goddess"))
            }
        }
    }

    // MARK: - Last period

    private let calendar = Calendar.current
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 15))! }

    func testNoDateChosenChangesNothing() {
        XCTAssertNil(OnboardingPeriodStart.plan(events: [], start: nil, today: today))
    }

    func testAChosenDateOnAnEmptyPhoneStartsACycleThroughTheLogPeriodPlan() throws {
        let start = calendar.date(byAdding: .day, value: -25, to: today)!
        let plan = try XCTUnwrap(OnboardingPeriodStart.plan(events: [], start: start, today: today))
        let expected = PeriodStartPlan.make(events: [], start: start, cycleLength: 28)
        XCTAssertEqual(plan.events.count, expected.events.count)
        XCTAssertTrue(plan.archive.isEmpty)
        XCTAssertEqual(calendar.startOfDay(for: plan.events.map(\.date).min()!), calendar.startOfDay(for: start))
        XCTAssertEqual(plan.events.first?.eventType, .menstrual)
    }

    func testMenopauseEntriesAreKept() throws {
        let entry = Event(eventType: .follicular, date: today, note: "", tags: "Menopause:Hot Flashes", mode: .menopause)
        let plan = try XCTUnwrap(OnboardingPeriodStart.plan(events: [entry], start: today, today: today))
        XCTAssertTrue(plan.events.contains { $0.id == entry.id })
    }

    func testExistingCycleDataIsNeverReplaced() {
        // A replay, or a restore made during onboarding: Log Period on Today is the way to start a new cycle.
        let existing = CycleGenerator.events(startDate: calendar.date(byAdding: .day, value: -10, to: today)!, cycleLength: 28)
        XCTAssertNil(OnboardingPeriodStart.plan(events: existing, start: today, today: today))
        XCTAssertTrue(OnboardingPeriodStart.hasCycleData(existing))
        XCTAssertFalse(OnboardingPeriodStart.hasCycleData([]))
    }

    func testAFutureDateIsNotUsed() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        XCTAssertNil(OnboardingPeriodStart.plan(events: [], start: tomorrow, today: today))
    }

    func testContinueWithoutChoosingADateLogsNothing() {
        // The picker shows today by default; Continue must not turn that default into a made-up cycle.
        XCTAssertNil(OnboardingPeriodStart.continuePlan(events: [], start: today, chosen: false, mode: .cycle, today: today))
        XCTAssertNil(OnboardingPeriodStart.continuePlan(events: [], start: today, chosen: false, mode: .planning, today: today))
    }

    func testContinueAfterChoosingADateLogsIt() throws {
        let start = calendar.date(byAdding: .day, value: -5, to: today)!
        let plan = try XCTUnwrap(OnboardingPeriodStart.continuePlan(events: [], start: start, chosen: true, mode: .cycle, today: today))
        XCTAssertEqual(calendar.startOfDay(for: plan.events.map(\.date).min()!), calendar.startOfDay(for: start))
    }

    func testMenopauseNeverLogsAPeriodFromOnboarding() {
        XCTAssertNil(OnboardingPeriodStart.continuePlan(events: [], start: today, chosen: true, mode: .menopause, today: today))
    }

    func testMenopauseSkipsTheLastPeriodPage() {
        XCTAssertEqual(OnboardingPage.pages(for: .menopause), [.welcome, .mode, .phases, .makeItYours])
        XCTAssertEqual(OnboardingPage.pages(for: .cycle), OnboardingPage.allCases)
        XCTAssertEqual(OnboardingPage.mode.next(for: .menopause), .phases)
        XCTAssertEqual(OnboardingPage.phases.previous(for: .menopause), .mode)
        XCTAssertEqual(OnboardingPage.mode.next(for: .cycle), .lastPeriod)
        XCTAssertEqual(OnboardingPage.phases.previous(for: .planning), .lastPeriod)
        XCTAssertEqual(OnboardingPage.phases.accessibilityPosition(for: .menopause), "Page 3 of 4")
        XCTAssertEqual(OnboardingPage.phases.accessibilityPosition(for: .cycle), "Page 4 of 5")
    }

    func testThePickerOffersTheLastFewMonthsUpToToday() {
        let range = OnboardingPeriodStart.pickerRange(today: today)
        XCTAssertEqual(calendar.startOfDay(for: range.upperBound), calendar.startOfDay(for: today))
        XCTAssertEqual(calendar.dateComponents([.day], from: range.lowerBound, to: calendar.startOfDay(for: today)).day,
                       OnboardingPeriodStart.daysBack)
    }

    // MARK: - Permissions primer

    func testPrimerListsThreeItemsAndAsksNothingUntilTapped() {
        XCTAssertEqual(OnboardingPrimer.Item.allCases, [.dailyInsights, .appleHealth, .appleCalendar])
        for item in OnboardingPrimer.Item.allCases {
            XCTAssertEqual(OnboardingPrimer().state(item), .idle)
            XCTAssertFalse(item.reason.isEmpty)
        }
    }

    func testEnableDailyInsightsAsksForNotificationsOnly() {
        XCTAssertEqual(OnboardingPrimer.Item.dailyInsights.enableAction(isPlus: false), .chooseLockScreenPrivacy)
        XCTAssertEqual(OnboardingPrimer.Item.appleHealth.enableAction(isPlus: false), .showInSettings)
        XCTAssertEqual(OnboardingPrimer.Item.appleCalendar.enableAction(isPlus: true), .showInSettings)
        XCTAssertEqual(OnboardingPrimer.Item.appleCalendar.enableAction(isPlus: false), .explainPlus)
    }

    func testEnableShowsTheLockScreenChoiceBeforeAnythingIsScheduled() {
        var primer = OnboardingPrimer()
        XCTAssertEqual(primer.lockScreenChoice, .keepPrivate, "private unless the person picks otherwise")
        primer.set(.dailyInsights, .choosingPrivacy)
        XCTAssertNotNil(OnboardingPrimer.Item.dailyInsights.detail(for: .choosingPrivacy))
        XCTAssertEqual(OnboardingPrimer.LockScreenChoice.allCases, [.showDetails, .keepPrivate])
        XCTAssertEqual(OnboardingPrimer.LockScreenChoice.showDetails.title, "Show details on the Lock Screen")
        XCTAssertEqual(OnboardingPrimer.LockScreenChoice.keepPrivate.title, "Keep it private")
        XCTAssertTrue(OnboardingPrimer.LockScreenChoice.keepPrivate.discreet)
        XCTAssertFalse(OnboardingPrimer.LockScreenChoice.showDetails.discreet)
        XCTAssertEqual(OnboardingPrimer.confirmAction, .requestNotifications, "only the confirm asks iOS")
    }

    func testTheLockScreenPreviewFollowsTheChoice() {
        let insights = TemplateInsightWriter().insights(for: InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 24))
        let hidden = OnboardingPrimer.preview(insights, choice: .keepPrivate)
        XCTAssertEqual(hidden.title, NotificationScheduler.discreetTitle)
        XCTAssertEqual(hidden.body, NotificationScheduler.discreetInsightBody)
        let shown = OnboardingPrimer.preview(insights, choice: .showDetails)
        XCTAssertEqual(shown, NotificationsPage.insightPreview(insights, discreet: false))
    }

    func testDailyInsightsIsOffByDefault() {
        let suite = UserDefaults(suiteName: "OnboardingFlowTests.defaults")!
        suite.removePersistentDomain(forName: "OnboardingFlowTests.defaults")
        XCTAssertFalse(DailyInsightsSetting.load(from: suite).isOn)
    }

    func testStatesAndTheirLines() {
        var primer = OnboardingPrimer()
        primer.set(.dailyInsights, .on)
        primer.set(.appleHealth, .later)
        XCTAssertEqual(primer.state(.dailyInsights), .on)
        XCTAssertFalse(primer.opensSettingsOnFinish)
        primer.set(.appleHealth, .inSettings)
        XCTAssertTrue(primer.opensSettingsOnFinish)
        XCTAssertNotNil(OnboardingPrimer.Item.dailyInsights.detail(for: .denied))
        XCTAssertNotNil(OnboardingPrimer.Item.appleCalendar.detail(for: .plusNeeded))
        XCTAssertNil(OnboardingPrimer.Item.appleHealth.detail(for: .idle))
    }
}
