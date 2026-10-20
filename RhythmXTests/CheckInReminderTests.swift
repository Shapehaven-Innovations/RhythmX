import XCTest
import UserNotifications
@testable import RhythmX

/// Daily and weekly check-ins: identifiers, weekday handling, and where a tap leads.
final class CheckInReminderTests: XCTestCase {
    private let checkInKeys = ["dailyCheckIn", "weeklyCheckIn"]
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

    // MARK: - Weekly

    func testWeeklyCheckInIsExactlyOneWeekday() throws {
        let weekly = CheckInSetting(isOn: true, hour: 18, minute: 0, weekdays: [1])
        let requests = NotificationScheduler.checkInRequests(daily: nil, weekly: weekly, mode: .cycle)

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].identifier, "rhythmx.checkin.weekly")
        let t = try trigger(requests[0])
        XCTAssertTrue(t.repeats)
        XCTAssertEqual(t.dateComponents.weekday, 1)
        XCTAssertEqual(t.dateComponents.hour, 18)
        XCTAssertEqual(t.dateComponents.minute, 0)

        // More than one weekday still yields exactly one request, on the first weekday of the week.
        let sloppy = CheckInSetting(isOn: true, hour: 18, minute: 0, weekdays: [5, 3])
        let one = NotificationScheduler.checkInRequests(daily: nil, weekly: sloppy, mode: .cycle)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(try trigger(one[0]).dateComponents.weekday, 3)

        // No weekday at all falls back to one weekday rather than every day.
        let none = CheckInSetting(isOn: true, hour: 18, minute: 0, weekdays: [])
        let fallback = NotificationScheduler.checkInRequests(daily: nil, weekly: none, mode: .cycle)
        XCTAssertEqual(fallback.count, 1)
        XCTAssertNotNil(try trigger(fallback[0]).dateComponents.weekday)
    }

    func testWeeklyCheckInRoutesToPatterns() throws {
        let weekly = CheckInSetting(isOn: true, hour: 18, minute: 0, weekdays: [1])
        let request = try XCTUnwrap(NotificationScheduler.checkInRequests(daily: nil, weekly: weekly, mode: .planning).first)

        XCTAssertEqual(request.content.userInfo["destination"] as? String, "weeklyReview")
        XCTAssertEqual(request.content.userInfo["destination"] as? String, LoggingReminder.Destination.weeklyReview.rawValue)
        XCTAssertNil(request.content.userInfo["category"])
    }

    // MARK: - Daily

    func testDailyCheckInOpensCurrentModeMainCategory() throws {
        let daily = CheckInSetting(isOn: true, hour: 20, minute: 0, weekdays: [])
        let expected: [TrackingMode: String] = [.cycle: "Symptom", .planning: "Planning", .menopause: "Menopause"]

        for (mode, category) in expected {
            let request = try XCTUnwrap(NotificationScheduler.checkInRequests(daily: daily, weekly: nil, mode: mode).first)
            XCTAssertEqual(request.content.userInfo["category"] as? String, category, "\(mode)")
            XCTAssertEqual(request.content.userInfo["destination"] as? String, "tagForm", "\(mode)")
        }
        XCTAssertEqual(TrackingMode.cycle.mainCategory, .symptom)
        XCTAssertEqual(TrackingMode.planning.mainCategory, .planning)
        XCTAssertEqual(TrackingMode.menopause.mainCategory, .menopause)
    }

    func testDailyCheckInEveryDayWhenNoWeekdays() throws {
        let daily = CheckInSetting(isOn: true, hour: 20, minute: 15, weekdays: [])
        let requests = NotificationScheduler.checkInRequests(daily: daily, weekly: nil, mode: .cycle)

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].identifier, "rhythmx.checkin.daily")
        let t = try trigger(requests[0])
        XCTAssertTrue(t.repeats)
        XCTAssertNil(t.dateComponents.weekday, "no weekday means the trigger repeats every day")
        XCTAssertEqual(t.dateComponents.hour, 20)
        XCTAssertEqual(t.dateComponents.minute, 15)
    }

    func testDailyCheckInOneRequestPerSelectedWeekday() throws {
        let daily = CheckInSetting(isOn: true, hour: 8, minute: 0, weekdays: [2, 4, 6])
        let requests = NotificationScheduler.checkInRequests(daily: daily, weekly: nil, mode: .menopause)

        XCTAssertEqual(Set(requests.map(\.identifier)),
                       ["rhythmx.checkin.daily.2", "rhythmx.checkin.daily.4", "rhythmx.checkin.daily.6"])
        XCTAssertEqual(Set(try requests.map { try trigger($0).dateComponents.weekday }), [2, 4, 6])
        for request in requests {
            XCTAssertTrue(request.identifier.hasPrefix(NotificationScheduler.checkInPrefix))
            XCTAssertEqual(request.content.userInfo["category"] as? String, "Menopause")
        }
    }

    func testCheckInsOffOrMissingProduceNothing() {
        let off = CheckInSetting(isOn: false, hour: 20, minute: 0, weekdays: [])
        XCTAssertEqual(NotificationScheduler.checkInRequests(daily: off, weekly: off, mode: .cycle), [])
        XCTAssertEqual(NotificationScheduler.checkInRequests(daily: nil, weekly: nil, mode: .cycle), [])

        let both = NotificationScheduler.checkInRequests(
            daily: CheckInSetting(isOn: true, hour: 20, minute: 0, weekdays: []),
            weekly: CheckInSetting(isOn: true, hour: 18, minute: 0, weekdays: [1]),
            mode: .cycle
        )
        XCTAssertEqual(Set(both.map(\.identifier)), ["rhythmx.checkin.daily", "rhythmx.checkin.weekly"])
    }

    // MARK: - Settings storage

    func testCheckInSettingsRoundTripThroughAppSettings() {
        let settings = AppSettings()
        XCTAssertNil(settings.dailyCheckIn)
        XCTAssertNil(settings.weeklyCheckIn)

        let daily = CheckInSetting(isOn: true, hour: 21, minute: 45, weekdays: [1, 7])
        let weekly = CheckInSetting(isOn: true, hour: 9, minute: 0, weekdays: [2])
        settings.dailyCheckIn = daily
        settings.weeklyCheckIn = weekly

        XCTAssertEqual(AppSettings().dailyCheckIn, daily)
        XCTAssertEqual(AppSettings().weeklyCheckIn, weekly)

        settings.dailyCheckIn = nil
        XCTAssertNil(AppSettings().dailyCheckIn)
        XCTAssertEqual(AppSettings().weeklyCheckIn, weekly)
    }

    func testDefaultCheckInsAreOff() {
        XCTAssertFalse(CheckInSetting.defaultDaily.isOn)
        XCTAssertFalse(CheckInSetting.defaultWeekly.isOn)
        XCTAssertEqual(CheckInSetting.defaultWeekly.weekdays.count, 1)
    }
}
