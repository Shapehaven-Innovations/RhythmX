import XCTest
@testable import RhythmX

/// The one-line summaries and the Lock Screen preview on the Notifications page.
final class NotificationsPageTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: - Summaries

    func testTimeIsShortAndPlain() {
        XCTAssertEqual(NotificationsPage.time(hour: 20, minute: 0, locale: locale, calendar: calendar), "8:00 PM")
        XCTAssertEqual(NotificationsPage.time(hour: 9, minute: 5, locale: locale, calendar: calendar), "9:05 AM")
    }

    func testPeriodSummary() {
        XCTAssertEqual(NotificationsPage.periodSummary(on: false, dayBefore: true, dayOf: true, locale: locale), "Off")
        XCTAssertEqual(NotificationsPage.periodSummary(on: true, dayBefore: true, dayOf: true, locale: locale),
                       "Day before and day of, at 8:00 AM")
        XCTAssertEqual(NotificationsPage.periodSummary(on: true, dayBefore: true, dayOf: false, locale: locale),
                       "The day before, at 8:00 AM")
        XCTAssertEqual(NotificationsPage.periodSummary(on: true, dayBefore: false, dayOf: true, locale: locale),
                       "On the day, at 8:00 AM")
        XCTAssertEqual(NotificationsPage.periodSummary(on: true, dayBefore: false, dayOf: false, locale: locale),
                       "On, but no day is picked")
    }

    func testFertileSummary() {
        XCTAssertEqual(NotificationsPage.fertileSummary(startOn: false, ovulationOn: false, mode: .cycle, locale: locale), "Off")
        XCTAssertEqual(NotificationsPage.fertileSummary(startOn: true, ovulationOn: false, mode: .cycle, locale: locale),
                       "When the window starts, at 8:00 AM")
        XCTAssertEqual(NotificationsPage.fertileSummary(startOn: false, ovulationOn: true, mode: .planning, locale: locale),
                       "Likely ovulation day, at 8:00 AM")
        XCTAssertEqual(NotificationsPage.fertileSummary(startOn: true, ovulationOn: true, mode: .cycle, locale: locale),
                       "Window start and likely ovulation, at 8:00 AM")
        XCTAssertEqual(NotificationsPage.fertileSummary(startOn: true, ovulationOn: true, mode: .menopause, locale: locale),
                       "Not scheduled in Menopause mode")
    }

    func testDailyInsightsSummary() {
        XCTAssertEqual(NotificationsPage.dailyInsightsSummary(on: false, hour: 20, minute: 0, locale: locale), "Off")
        XCTAssertEqual(NotificationsPage.dailyInsightsSummary(on: true, hour: 20, minute: 0, locale: locale),
                       "8:00 PM, opens a quick log")
    }

    func testDiscreetSummary() {
        XCTAssertEqual(NotificationsPage.discreetSummary(on: true), "Every notification hides its details")
        XCTAssertEqual(NotificationsPage.discreetSummary(on: false), "Notifications show details when locked")
    }

    func testWeeklySummary() {
        XCTAssertEqual(NotificationsPage.weeklySummary(nil, locale: locale, calendar: calendar), "Off")
        XCTAssertEqual(NotificationsPage.weeklySummary(.defaultWeekly, locale: locale, calendar: calendar), "Off")
        var on = CheckInSetting.defaultWeekly
        on.isOn = true
        XCTAssertEqual(NotificationsPage.weeklySummary(on, locale: locale, calendar: calendar), "Every Sunday at 6:00 PM")
    }

    func testOnCountForSettings() {
        XCTAssertEqual(NotificationsPage.onCount(period: true, fertile: false, dailyInsights: true, weeklyReview: true), 3)
        XCTAssertEqual(NotificationsPage.onCount(period: false, fertile: false, dailyInsights: false, weeklyReview: false), 0)
    }

    func testSummariesArePlainCopy() {
        let all = [
            NotificationsPage.periodSummary(on: true, dayBefore: true, dayOf: true, locale: locale),
            NotificationsPage.fertileSummary(startOn: true, ovulationOn: true, mode: .menopause, locale: locale),
            NotificationsPage.dailyInsightsSummary(on: true, hour: 9, minute: 0, locale: locale),
            NotificationsPage.discreetSummary(on: true),
            NotificationsPage.footer,
        ]
        for text in all {
            XCTAssertFalse(text.contains("\u{2014}"))
            XCTAssertFalse(text.unicodeScalars.contains { $0.properties.isEmojiPresentation })
        }
        XCTAssertFalse(NotificationsPage.footer.isEmpty)
    }

    // MARK: - Preview

    private var luteal: DailyInsights {
        TemplateInsightWriter().insights(for: InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 26, daysUntilPeriod: 3))
    }

    func testPreviewShowsTodaysNoteAsScheduled() {
        let preview = NotificationsPage.insightPreview(luteal, discreet: false)
        XCTAssertEqual(preview.title, "Cycle day 26")
        XCTAssertEqual(preview.body, "\(luteal.notificationBody) \(NotificationScheduler.insightLogNudge)")
        XCTAssertEqual(preview.title, NotificationScheduler.insightContent(luteal, discreet: false).title)
    }

    func testPreviewSwitchesToDiscreetText() {
        let preview = NotificationsPage.insightPreview(luteal, discreet: true)
        XCTAssertEqual(preview.title, NotificationScheduler.discreetInsightTitle)
        XCTAssertEqual(preview.body, NotificationScheduler.discreetInsightBody)
        XCTAssertFalse(preview.body.contains("26"))
    }

    func testPeriodPreviewUsesTheScheduledText() {
        let now = date(2026, 10, 20, 12)
        let predicted = date(2026, 10, 23, 0)
        let both = NotificationsPage.periodPreview(predicted: predicted, dayBefore: true, dayOf: true, now: now,
                                                   calendar: calendar)
        XCTAssertEqual(both?.title, NotificationScheduler.periodTitle)
        XCTAssertEqual(both?.body, NotificationScheduler.periodDayBeforeBody)
        XCTAssertEqual(both?.fire, date(2026, 10, 22, 8))

        let dayOf = NotificationsPage.periodPreview(predicted: predicted, dayBefore: false, dayOf: true, now: now,
                                                    calendar: calendar)
        XCTAssertEqual(dayOf?.body, NotificationScheduler.periodDayOfBody)
        XCTAssertEqual(dayOf?.fire, date(2026, 10, 23, 8))

        XCTAssertNil(NotificationsPage.periodPreview(predicted: nil, dayBefore: true, dayOf: true, now: now, calendar: calendar))
        XCTAssertNil(NotificationsPage.periodPreview(predicted: date(2026, 10, 1), dayBefore: true, dayOf: true, now: now,
                                                     calendar: calendar))
    }

    func testPeriodPreviewSkipsADayBeforeThatHasPassed() {
        let now = date(2026, 10, 22, 9)       // the day-before reminder at 8:00 has gone
        let predicted = date(2026, 10, 23, 0)
        let next = NotificationsPage.periodPreview(predicted: predicted, dayBefore: true, dayOf: true, now: now,
                                                   calendar: calendar)
        XCTAssertEqual(next?.body, NotificationScheduler.periodDayOfBody)
    }

    func testWhenLabel() {
        let now = date(2026, 10, 20, 12)
        XCTAssertEqual(NotificationsPage.whenLabel(date(2026, 10, 20, 20), now: now, locale: locale, calendar: calendar), "8:00 PM")
        XCTAssertEqual(NotificationsPage.whenLabel(date(2026, 10, 22, 8), now: now, locale: locale, calendar: calendar), "Thu 8:00 AM")
    }
}
