import XCTest
import UserNotifications
@testable import RhythmX

/// The weekly review check-in: identifier, weekday handling, and where a tap leads. (The daily check-in was
/// replaced by Daily insights, see DailyInsightsNotificationTests.)
final class CheckInReminderTests: XCTestCase {
    private let checkInKeys = ["weeklyCheckIn"]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        saved = [:]
        for key in checkInKeys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in checkInKeys { UserDefaults.standard.set(saved[key], forKey: key) }
        super.tearDown()
    }

    private func trigger(_ request: UNNotificationRequest, file: StaticString = #filePath, line: UInt = #line) throws -> UNCalendarNotificationTrigger {
        try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger, file: file, line: line)
    }

    func testWeeklyCheckInIsExactlyOneWeekday() throws {
        let weekly = CheckInSetting(isOn: true, hour: 18, minute: 0, weekdays: [1])
        let requests = NotificationScheduler.checkInRequests(weekly: weekly)

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].identifier, "rhythmx.checkin.weekly")
        XCTAssertTrue(requests[0].identifier.hasPrefix(NotificationScheduler.checkInPrefix))
        let t = try trigger(requests[0])
        XCTAssertTrue(t.repeats)
        XCTAssertEqual(t.dateComponents.weekday, 1)
        XCTAssertEqual(t.dateComponents.hour, 18)
        XCTAssertEqual(t.dateComponents.minute, 0)

        // More than one weekday still yields exactly one request, on the first weekday of the week.
        let sloppy = CheckInSetting(isOn: true, hour: 18, minute: 0, weekdays: [5, 3])
        let one = NotificationScheduler.checkInRequests(weekly: sloppy)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(try trigger(one[0]).dateComponents.weekday, 3)

        // No weekday at all falls back to one weekday rather than every day.
        let none = CheckInSetting(isOn: true, hour: 18, minute: 0, weekdays: [])
        let fallback = NotificationScheduler.checkInRequests(weekly: none)
        XCTAssertEqual(fallback.count, 1)
        XCTAssertNotNil(try trigger(fallback[0]).dateComponents.weekday)
    }

    func testWeeklyCheckInRoutesToPatterns() throws {
        let weekly = CheckInSetting(isOn: true, hour: 18, minute: 0, weekdays: [1])
        let request = try XCTUnwrap(NotificationScheduler.checkInRequests(weekly: weekly).first)

        XCTAssertEqual(request.content.userInfo["destination"] as? String, "weeklyReview")
        XCTAssertEqual(request.content.userInfo["destination"] as? String, NotificationScheduler.Destination.weeklyReview.rawValue)
        XCTAssertNil(request.content.userInfo["category"])
        XCTAssertEqual(NotificationTapRouter.route(for: request.content.userInfo)?.name, .rhythmxOpenPatterns)
    }

    func testWeeklyCheckInOffOrMissingProducesNothing() {
        XCTAssertEqual(NotificationScheduler.checkInRequests(weekly: CheckInSetting(isOn: false, hour: 20, minute: 0, weekdays: [1])), [])
        XCTAssertEqual(NotificationScheduler.checkInRequests(weekly: nil), [])
    }

    func testWeeklyCheckInRoundTripsThroughAppSettings() {
        let settings = AppSettings()
        XCTAssertNil(settings.weeklyCheckIn)

        let weekly = CheckInSetting(isOn: true, hour: 9, minute: 0, weekdays: [2])
        settings.weeklyCheckIn = weekly
        XCTAssertEqual(AppSettings().weeklyCheckIn, weekly)

        settings.weeklyCheckIn = nil
        XCTAssertNil(AppSettings().weeklyCheckIn)
    }

    func testDefaultWeeklyCheckInIsOffOnOneDay() {
        XCTAssertFalse(CheckInSetting.defaultWeekly.isOn)
        XCTAssertEqual(CheckInSetting.defaultWeekly.weekdays.count, 1)
    }
}
