import XCTest
import UserNotifications
@testable import RhythmX

/// Tag reminders: `LoggingReminder`, `ReminderStore` and the pure request builder behind
/// `NotificationScheduler.scheduleLoggingReminders`, plus the backup shape they travel in.
final class LoggingReminderTests: XCTestCase {
    private var suite: UserDefaults!
    private let suiteName = "LoggingReminderTests.suite"

    override func setUp() {
        super.setUp()
        suite = UserDefaults(suiteName: suiteName)
        suite.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Fixtures

    private func reminder(_ title: String, mode: TrackingMode, category: TagCategory = .symptom,
                          weekdays: Set<Int> = [2], hour: Int = 21, minute: Int = 0, isOn: Bool = true,
                          destination: LoggingReminder.Destination = .tagForm) -> LoggingReminder {
        LoggingReminder(title: title, hour: hour, minute: minute, weekdays: weekdays,
                        category: category, mode: mode, isOn: isOn, destination: destination)
    }

    private func calendarTrigger(_ request: UNNotificationRequest, file: StaticString = #filePath, line: UInt = #line) throws -> UNCalendarNotificationTrigger {
        try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger, "expected a calendar trigger", file: file, line: line)
    }

    // MARK: - Request building

    func testDisplayTitleFallsBackToCategoryName() {
        XCTAssertEqual(reminder("Log temperature", mode: .planning, category: .basalTemp).displayTitle, "Log temperature")
        XCTAssertEqual(reminder("", mode: .cycle, category: .symptom).displayTitle, TagCategory.symptom.rawValue)
        XCTAssertEqual(reminder("   ", mode: .menopause, category: .menopause).displayTitle, TagCategory.menopause.rawValue,
                       "whitespace is not a title")
    }

    func testRequestsOnlyForActiveModeAndOnReminders() {
        let cycleOn = reminder("Log symptoms", mode: .cycle)
        let cycleOff = reminder("Log mood", mode: .cycle, category: .mood, isOn: false)
        let planningOn = reminder("Log temperature", mode: .planning, category: .basalTemp)
        let menopauseOn = reminder("Night sweats and sleep", mode: .menopause, category: .menopause)

        let requests = NotificationScheduler.requests(for: [cycleOn, cycleOff, planningOn, menopauseOn], activeMode: .cycle)

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.identifier, "rhythmx.reminder.\(cycleOn.id.uuidString).2")
        XCTAssertEqual(requests.first?.content.title, "Log symptoms")
    }

    func testOneRequestPerSelectedWeekday() {
        let r = reminder("Log symptoms", mode: .cycle, weekdays: [1, 4, 7])
        let requests = NotificationScheduler.requests(for: [r], activeMode: .cycle)

        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(Set(requests.map(\.identifier)),
                       Set([1, 4, 7].map { "rhythmx.reminder.\(r.id.uuidString).\($0)" }))
    }

    func testEmptyWeekdaysMeansEveryDay() throws {
        let r = reminder("Log symptoms", mode: .cycle, weekdays: [])
        let requests = NotificationScheduler.requests(for: [r], activeMode: .cycle)

        XCTAssertEqual(requests.count, 7)
        let weekdays = try requests.map { try calendarTrigger($0).dateComponents.weekday }
        XCTAssertEqual(Set(weekdays.compactMap { $0 }), Set(1...7))
    }

    func testTriggerComponentsHourMinuteWeekdayRepeats() throws {
        let r = reminder("Ovulation test", mode: .planning, category: .planning, weekdays: [5], hour: 12, minute: 30)
        let request = try XCTUnwrap(NotificationScheduler.requests(for: [r], activeMode: .planning).first)
        let trigger = try calendarTrigger(request)

        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 12)
        XCTAssertEqual(trigger.dateComponents.minute, 30)
        XCTAssertEqual(trigger.dateComponents.weekday, 5)
        XCTAssertNil(trigger.dateComponents.year, "a repeating weekday trigger carries no date")
        XCTAssertNil(trigger.dateComponents.day)
    }

    func testIdentifiersUsePrefix() {
        let reminders = [
            reminder("A", mode: .cycle, weekdays: [1, 2]),
            reminder("B", mode: .cycle, category: .mood, weekdays: [3])
        ]
        let requests = NotificationScheduler.requests(for: reminders, activeMode: .cycle)

        XCTAssertEqual(requests.count, 3)
        for request in requests {
            XCTAssertTrue(request.identifier.hasPrefix(NotificationScheduler.reminderPrefix), request.identifier)
            XCTAssertTrue(request.identifier.hasPrefix("rhythmx.reminder."), request.identifier)
        }
        XCTAssertEqual(Set(requests.map(\.identifier)).count, 3, "identifiers are unique per reminder and weekday")
    }

    func testUserInfoCarriesCategoryAndDestination() throws {
        let r = reminder("Log temperature", mode: .planning, category: .basalTemp)
        let request = try XCTUnwrap(NotificationScheduler.requests(for: [r], activeMode: .planning).first)

        XCTAssertEqual(request.content.userInfo["category"] as? String, TagCategory.basalTemp.rawValue)
        XCTAssertEqual(request.content.userInfo["destination"] as? String, LoggingReminder.Destination.tagForm.rawValue)
    }

    func testSwitchingModeSchedulesOtherModesReminders() {
        let reminders = [
            reminder("Log symptoms", mode: .cycle),
            reminder("Log temperature", mode: .planning, category: .basalTemp, weekdays: [2]),
            reminder("Ovulation test", mode: .planning, category: .planning, weekdays: [2]),
            reminder("Night sweats and sleep", mode: .menopause, category: .menopause)
        ]

        let cycle = NotificationScheduler.requests(for: reminders, activeMode: .cycle)
        let planning = NotificationScheduler.requests(for: reminders, activeMode: .planning)
        let menopause = NotificationScheduler.requests(for: reminders, activeMode: .menopause)

        XCTAssertEqual(cycle.map(\.content.title), ["Log symptoms"])
        XCTAssertEqual(Set(planning.map(\.content.title)), ["Log temperature", "Ovulation test"])
        XCTAssertEqual(menopause.map(\.content.title), ["Night sweats and sleep"])
        // The same saved list serves every mode; nothing is lost when the mode changes.
        XCTAssertEqual(reminders.count, 4)
    }

    // MARK: - Store

    func testReminderStoreRoundTrip() {
        let reminders = [
            reminder("Log symptoms", mode: .cycle, weekdays: [1, 2, 3], hour: 21, minute: 15),
            reminder("Ovulation test", mode: .planning, category: .planning, weekdays: [], hour: 12, minute: 0, isOn: false)
        ]

        ReminderStore.save(reminders, defaults: suite)
        XCTAssertEqual(ReminderStore.load(defaults: suite), reminders)
        XCTAssertNotNil(suite.data(forKey: "loggingReminders"))

        ReminderStore.save([], defaults: suite)
        XCTAssertEqual(ReminderStore.load(defaults: suite), [], "an emptied list stays empty, it does not fall back to the defaults")
    }

    func testDefaultRemindersAreOffAndCoverEachMode() {
        let defaults = ReminderStore.load(defaults: suite)

        XCTAssertFalse(defaults.isEmpty)
        XCTAssertTrue(defaults.allSatisfy { !$0.isOn }, "default reminders start off")
        XCTAssertEqual(defaults.filter { $0.mode == .cycle }.map(\.title), ["Log symptoms"])
        XCTAssertEqual(Set(defaults.filter { $0.mode == .planning }.map(\.title)), ["Log temperature", "Ovulation test"])
        XCTAssertEqual(Set(defaults.filter { $0.mode == .menopause }.map(\.title)), ["Night sweats and sleep", "Log symptoms"])

        let temperature = defaults.first { $0.title == "Log temperature" }
        XCTAssertEqual(temperature?.category, .basalTemp)
        XCTAssertEqual(temperature?.hour, 7)
        let test = defaults.first { $0.title == "Ovulation test" }
        XCTAssertEqual(test?.category, .planning)
        XCTAssertEqual(test?.hour, 12)
        XCTAssertEqual(defaults.first { $0.mode == .cycle }?.hour, 21)
        XCTAssertEqual(defaults.first { $0.title == "Night sweats and sleep" }?.hour, 7)
        XCTAssertEqual(defaults.first { $0.title == "Night sweats and sleep" }?.minute, 30)
        XCTAssertTrue(defaults.allSatisfy { $0.destination == .tagForm })
    }

    // MARK: - Backup shape

    private func baseSettings() -> BackupSettings {
        BackupSettings(
            phaseColors: ["#111111", "#222222", "#333333", "#444444"],
            notificationsEnabled: true,
            notifyDayBefore: true,
            notifyDayOf: false,
            fertileStartOn: true,
            fertileOvulationOn: false,
            trackingMode: "planning",
            defaultModeOnLaunch: "last",
            themeID: "default",
            reminders: [reminder("Ovulation test", mode: .planning, category: .planning, weekdays: [2, 4], hour: 12)],
            dailyCheckIn: CheckInSetting(isOn: true, hour: 20, minute: 0, weekdays: []),
            weeklyCheckIn: CheckInSetting(isOn: true, hour: 18, minute: 30, weekdays: [1])
        )
    }

    func testBackupSettingsRoundTripWithRemindersAndCheckIns() throws {
        let payload = BackupPayload(events: [], archivedBlocks: [], settings: baseSettings())
        let data = try BackupFile.make(payload, appVersion: "2.0.0", passphrase: nil)
        let restored = try BackupFile.open(data, passphrase: nil)

        XCTAssertEqual(restored.settings, payload.settings)
        XCTAssertEqual(restored.settings.reminders?.first?.weekdays, [2, 4])
        XCTAssertEqual(restored.settings.weeklyCheckIn?.weekdays, [1])
    }

    /// Phase 1 wrote format-1 files with `reminders: [String]` and `dailyCheckIn/weeklyCheckIn: String?`.
    /// Those files must still open; the placeholder values read as "no reminders, no check-ins".
    func testFormatOneBackupWithPlaceholderShapesStillOpens() throws {
        let settingsJSON: [String: Any] = [
            "phaseColors": ["#111111", "#222222", "#333333", "#444444"],
            "notificationsEnabled": true,
            "notifyDayBefore": false,
            "notifyDayOf": true,
            "fertileStartOn": false,
            "fertileOvulationOn": true,
            "trackingMode": "cycle",
            "defaultModeOnLaunch": "menopause",
            "themeID": "default",
            "reminders": ["old placeholder", "another"],
            "dailyCheckIn": "20:00",
            "weeklyCheckIn": NSNull()
        ]
        let payloadJSON: [String: Any] = ["events": [], "archivedBlocks": [], "settings": settingsJSON]
        let body = try JSONSerialization.data(withJSONObject: payloadJSON)
        let envelope: [String: Any] = [
            "formatVersion": 1,
            "appVersion": "2.0.0",
            "createdAt": "2026-10-19T10:00:00Z",
            "encrypted": false,
            "body": body.base64EncodedString()
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)

        let restored = try BackupFile.open(data, passphrase: nil)

        XCTAssertNil(restored.settings.reminders, "placeholder reminders are unknown, so a restore leaves the stored list alone")
        XCTAssertNil(restored.settings.dailyCheckIn)
        XCTAssertNil(restored.settings.weeklyCheckIn)
        // The fields around the placeholders are read as before.
        XCTAssertTrue(restored.settings.notificationsEnabled)
        XCTAssertTrue(restored.settings.notifyDayOf)
        XCTAssertTrue(restored.settings.fertileOvulationOn)
        XCTAssertEqual(restored.settings.defaultModeOnLaunch, "menopause")
        XCTAssertEqual(restored.settings.phaseColors.count, 4)
    }
}
