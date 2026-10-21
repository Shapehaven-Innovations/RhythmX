import XCTest
import UserNotifications
@testable import RhythmX

/// Lock Screen privacy: one switch makes every RhythmX notification neutral (period, fertile window, weekly
/// review and Daily insights).
final class LockScreenPrivacyTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func assertNeutral(_ title: String, _ body: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(title, NotificationScheduler.discreetTitle, file: file, line: line)
        XCTAssertTrue([NotificationScheduler.discreetReminderBody, NotificationScheduler.discreetInsightBody].contains(body),
                      body, file: file, line: line)
        for word in ["period", "cycle", "fertile", "ovulation", "pattern", "menstrual"] {
            XCTAssertFalse((title + " " + body).lowercased().contains(word), word, file: file, line: line)
        }
    }

    func testNeutralTextIsPlain() {
        XCTAssertEqual(NotificationScheduler.discreetTitle, "RhythmX")
        XCTAssertEqual(NotificationScheduler.discreetReminderBody, "A reminder from RhythmX")
        XCTAssertEqual(NotificationScheduler.discreetInsightBody, "Your daily note is ready")
    }

    func testPeriodRemindersAreNeutralWhenPrivate() {
        for dayBefore in [true, false] {
            let text = NotificationScheduler.periodContent(dayBefore: dayBefore, discreet: true)
            assertNeutral(text.title, text.body)
        }
        let open = NotificationScheduler.periodContent(dayBefore: true, discreet: false)
        XCTAssertEqual(open.title, NotificationScheduler.periodTitle)
        XCTAssertEqual(open.body, NotificationScheduler.periodDayBeforeBody)
        XCTAssertEqual(NotificationScheduler.periodContent(dayBefore: false, discreet: false).body,
                       NotificationScheduler.periodDayOfBody)
    }

    func testFertileRemindersAreNeutralWhenPrivate() {
        let now = date(2026, 10, 1)
        let window = date(2026, 10, 10)...date(2026, 10, 15)
        let requests = NotificationScheduler.fertileRequests(window: window, ovulation: date(2026, 10, 15), startOn: true,
                                                             ovulationOn: true, mode: .planning, now: now,
                                                             calendar: calendar, discreet: true)
        XCTAssertEqual(requests.count, 2)
        for request in requests { assertNeutral(request.content.title, request.content.body) }
        let open = NotificationScheduler.fertileRequests(window: window, ovulation: date(2026, 10, 15), startOn: true,
                                                         ovulationOn: true, mode: .planning, now: now, calendar: calendar)
        XCTAssertEqual(open.first?.content.title, "Fertile window")
    }

    func testWeeklyReviewIsNeutralWhenPrivate() {
        let weekly = CheckInSetting(isOn: true, hour: 18, minute: 0, weekdays: [1])
        let requests = NotificationScheduler.checkInRequests(weekly: weekly, discreet: true)
        XCTAssertEqual(requests.count, 1)
        assertNeutral(requests[0].content.title, requests[0].content.body)
        XCTAssertEqual(requests[0].content.userInfo["destination"] as? String,
                       NotificationScheduler.Destination.weeklyReview.rawValue, "a tap still opens Patterns")
        XCTAssertEqual(NotificationScheduler.checkInRequests(weekly: weekly).first?.content.title, "Weekly check-in")
    }

    func testPeriodPreviewFollowsTheSwitch() {
        let preview = NotificationsPage.periodPreview(predicted: date(2026, 10, 23, 0), dayBefore: true, dayOf: true,
                                                      now: date(2026, 10, 20), calendar: calendar, discreet: true)
        XCTAssertEqual(preview?.title, NotificationScheduler.discreetTitle)
        XCTAssertEqual(preview?.body, NotificationScheduler.discreetReminderBody)
    }

    func testTheSwitchIsReadFromTheSharedStore() {
        let suite = UserDefaults(suiteName: "LockScreenPrivacyTests")!
        suite.removePersistentDomain(forName: "LockScreenPrivacyTests")
        XCTAssertFalse(NotificationScheduler.isDiscreet(defaults: suite))
        suite.set(true, forKey: AppSettings.dailyInsightsDiscreetKey)
        XCTAssertTrue(NotificationScheduler.isDiscreet(defaults: suite))
        suite.removePersistentDomain(forName: "LockScreenPrivacyTests")
    }

    func testInfoCopyDescribesEveryNotification() {
        let topic = InfoCopy.discreetLockScreen
        XCTAssertEqual(topic.title, "Lock Screen privacy")
        let text = topic.paragraphs.joined(separator: " ")
        for part in ["period", "fertile window", "weekly review", "Daily insights",
                     NotificationScheduler.discreetReminderBody, NotificationScheduler.discreetInsightBody] {
            XCTAssertTrue(text.contains(part), part)
        }
        XCTAssertEqual(NotificationsPage.discreetSummary(on: true), "Every notification hides its details")
        XCTAssertEqual(NotificationsPage.discreetSummary(on: false), "Notifications show details when locked")
    }
}
