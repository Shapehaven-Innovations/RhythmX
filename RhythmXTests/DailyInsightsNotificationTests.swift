import XCTest
import UserNotifications
@testable import RhythmX

// MARK: - Fakes

/// Stands in for `UNUserNotificationCenter`: keeps pending requests in memory.
private final class FakeCenter: InsightNotificationCenter, @unchecked Sendable {
    var authorized = true
    var pending: [UNNotificationRequest] = []
    var removed: [String] = []

    func isAuthorizedForInsights() async -> Bool { authorized }
    func pendingIdentifiers() async -> [String] { pending.map(\.identifier) }
    func removePending(_ identifiers: [String]) {
        removed += identifiers
        pending.removeAll { identifiers.contains($0.identifier) }
    }
    func addRequest(_ request: UNNotificationRequest) async {
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func request(_ id: String) -> UNNotificationRequest? { pending.first { $0.identifier == id } }
    var insightIDs: [String] { pending.map(\.identifier).filter { $0.hasPrefix(NotificationScheduler.insightPrefix) }.sorted() }

    static func placeholder(_ id: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "old"
        return UNNotificationRequest(identifier: id, content: content, trigger: nil)
    }
}

/// A writer that marks its mood line, so a test can tell written text from the template.
private final class MarkingWriter: InsightWriting, @unchecked Sendable {
    var isModelAvailable: Bool { true }
    var calls = 0
    var cancelsCurrentTask = false

    func insights(for facts: InsightFacts) async -> DailyInsights {
        calls += 1
        if cancelsCurrentTask { withUnsafeCurrentTask { $0?.cancel() } }
        var day = TemplateInsightWriter().insights(for: facts)
        day.moodLine = "Written on this phone."
        day.notificationBody = "Written on this phone."
        day.moodLineIsAI = true
        return day
    }
}

/// A center whose first `pendingIdentifiers` call waits until the test opens the gate, so a run can be held
/// in the middle while a newer one starts.
private final class GatedCenter: InsightNotificationCenter, @unchecked Sendable {
    let inner = FakeCenter()
    private let lock = NSLock()
    private var calls = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var opened = false
    var onFirstWait: () -> Void = {}

    func isAuthorizedForInsights() async -> Bool { true }
    func pendingIdentifiers() async -> [String] {
        lock.lock(); calls += 1; let first = calls == 1; lock.unlock()
        if first {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                lock.lock()
                if opened { lock.unlock(); c.resume(); return }
                gate = c
                lock.unlock()
                onFirstWait()
            }
        }
        return await inner.pendingIdentifiers()
    }
    func removePending(_ identifiers: [String]) { inner.removePending(identifiers) }
    func addRequest(_ request: UNNotificationRequest) async { await inner.addRequest(request) }

    func open() {
        lock.lock(); opened = true; let c = gate; gate = nil; lock.unlock()
        c?.resume()
    }
}

final class DailyInsightsNotificationTests: XCTestCase {
    private let calendar = Calendar.current
    private let suiteName = "DailyInsightsNotificationTests.suite"
    private var suite: UserDefaults!

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

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var cycleEvents: [Event] { CycleGenerator.events(startDate: at(1, 0), cycleLength: 28) }

    private let on = DailyInsightsSetting(isOn: true, hour: 9, minute: 0, discreet: false)

    private func requests(_ setting: DailyInsightsSetting? = nil, authorized: Bool = true, mode: TrackingMode = .cycle,
                          events: [Event]? = nil, now: Date? = nil,
                          written: @escaping (Date, InsightFacts) -> DailyInsights? = { _, _ in nil }) -> [UNNotificationRequest] {
        NotificationScheduler.dailyInsightRequests(setting: setting ?? on, authorized: authorized, mode: mode,
                                                   events: events ?? cycleEvents, archivedBlocks: [],
                                                   overrides: FertileOverrides(), now: now ?? at(20, 10),
                                                   calendar: calendar, written: written)
    }

    private func input(_ setting: DailyInsightsSetting? = nil, mode: TrackingMode = .cycle) -> DailyInsightsInput {
        DailyInsightsInput(setting: setting ?? on, mode: mode, events: cycleEvents, archivedBlocks: [],
                           overrides: FertileOverrides())
    }

    private func notifier(_ center: FakeCenter, writer: InsightWriting = MarkingWriter(), now: Date? = nil,
                          reloaded: @escaping () -> Void = {}) -> DailyInsightsNotifier {
        let clock = now ?? at(20, 10)
        return DailyInsightsNotifier(center: center, writer: writer, cache: suite, calendar: calendar,
                                     now: { clock }, reloadWidgets: reloaded)
    }

    // MARK: - Setting

    func testSettingDefaultsAreOffAtNine() {
        let setting = DailyInsightsSetting.load(from: suite)
        XCTAssertEqual(setting, DailyInsightsSetting(isOn: false, hour: 9, minute: 0, discreet: false))
    }

    func testSettingLoadsStoredKeys() {
        suite.set(true, forKey: AppSettings.dailyInsightsOnKey)
        suite.set(20, forKey: AppSettings.dailyInsightsHourKey)
        suite.set(15, forKey: AppSettings.dailyInsightsMinuteKey)
        suite.set(true, forKey: AppSettings.dailyInsightsDiscreetKey)
        XCTAssertEqual(DailyInsightsSetting.load(from: suite), DailyInsightsSetting(isOn: true, hour: 20, minute: 15, discreet: true))
    }

    func testFireDatesSkipATimeAlreadyPassedToday() {
        XCTAssertEqual(on.fireDates(after: at(20, 10), count: 2, calendar: calendar), [at(21, 9), at(22, 9)])
        XCTAssertEqual(on.fireDates(after: at(20, 8), count: 2, calendar: calendar), [at(20, 9), at(21, 9)])
        XCTAssertEqual(on.fireDates(after: at(20, 9), count: 1, calendar: calendar), [at(21, 9)], "exactly now is already past")
    }

    // MARK: - Requests

    func testSevenRequestsForTheNextSevenDaysAtTheChosenTime() throws {
        let all = requests()
        XCTAssertEqual(all.map(\.identifier), (21...27).map { "rhythmx.insight.2026-10-\($0)" })
        for request in all {
            let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
            XCTAssertFalse(trigger.repeats)
            XCTAssertEqual(trigger.dateComponents.hour, 9)
            XCTAssertEqual(trigger.dateComponents.minute, 0)
            XCTAssertGreaterThan(try XCTUnwrap(calendar.date(from: trigger.dateComponents)), at(20, 10), "never in the past")
        }
    }

    func testTodayIsIncludedWhileItsTimeIsAhead() {
        XCTAssertEqual(requests(now: at(20, 8, 59)).first?.identifier, "rhythmx.insight.2026-10-20")
        XCTAssertEqual(requests(now: at(20, 8, 59)).count, 7)
    }

    func testNothingWhenOffOrNotAuthorized() {
        XCTAssertEqual(requests(DailyInsightsSetting(isOn: false, hour: 9, minute: 0, discreet: false)), [])
        XCTAssertEqual(requests(authorized: false), [])
    }

    func testRequestCarriesTheDaysTemplateNoteAndOpensQuickLog() throws {
        let first = try XCTUnwrap(requests().first)
        let facts = InsightFacts.make(events: cycleEvents, archivedBlocks: [], mode: .cycle, today: at(21, 9), calendar: calendar)
        let template = TemplateInsightWriter().insights(for: facts)

        XCTAssertEqual(first.content.title, template.notificationTitle)
        XCTAssertTrue(first.content.title.hasPrefix("Cycle day "), first.content.title)
        XCTAssertEqual(first.content.body, "\(template.notificationBody) \(NotificationScheduler.insightLogNudge)")
        XCTAssertEqual(first.content.userInfo["destination"] as? String, "quickLog")
        XCTAssertEqual(NotificationScheduler.Destination.quickLog.rawValue, "quickLog")
    }

    func testDiscreetShowsOnlyNeutralText() {
        let discreet = DailyInsightsSetting(isOn: true, hour: 9, minute: 0, discreet: true)
        for request in requests(discreet) {
            XCTAssertEqual(request.content.title, "RhythmX")
            XCTAssertEqual(request.content.body, "Your daily note is ready")
            XCTAssertEqual(request.content.userInfo["destination"] as? String, "quickLog")
        }
    }

    func testMenopauseNotesCarryNoCycleDetails() {
        for request in requests(mode: .menopause) {
            XCTAssertEqual(request.content.title, "Your daily note")
            XCTAssertFalse(request.content.body.localizedCaseInsensitiveContains("cycle day"))
            XCTAssertFalse(request.content.body.localizedCaseInsensitiveContains("period may"))
        }
    }

    func testCopyIsPlain() {
        let all = requests() + requests(mode: .planning) + requests(mode: .menopause)
            + requests(DailyInsightsSetting(isOn: true, hour: 9, minute: 0, discreet: true))
        for request in all {
            let text = request.content.title + " " + request.content.body
            for banned in ["goddess", "\u{2014}", "\u{2013}"] { XCTAssertFalse(text.lowercased().contains(banned), text) }
        }
    }

    func testWrittenTextReplacesTheTemplateForThatDayOnly() {
        let all = requests { fire, _ in
            guard Calendar.current.isDate(fire, inSameDayAs: self.at(21, 9)) else { return nil }
            var day = TemplateInsightWriter().insights(for: InsightFacts(mode: .cycle))
            day.notificationTitle = "Day 21"
            day.notificationBody = "Written."
            return day
        }
        XCTAssertEqual(all[0].content.title, "Day 21")
        XCTAssertEqual(all[0].content.body, "Written. \(NotificationScheduler.insightLogNudge)")
        XCTAssertNotEqual(all[1].content.body, "Written. \(NotificationScheduler.insightLogNudge)")
    }

    // MARK: - Notifier

    func testRefreshReplacesOnlyInsightRequestsAndWritesTheNextNote() async {
        let center = FakeCenter()
        center.pending = [FakeCenter.placeholder("rhythmx.insight.2026-10-01"), FakeCenter.placeholder("rhythmx.fertile.start"),
                          FakeCenter.placeholder("rhythmx.checkin.weekly")]
        var reloads = 0
        await notifier(center, reloaded: { reloads += 1 }).refresh(input())

        XCTAssertEqual(center.insightIDs, (21...27).map { "rhythmx.insight.2026-10-\($0)" })
        XCTAssertNotNil(center.request("rhythmx.fertile.start"), "other reminders are untouched")
        XCTAssertNotNil(center.request("rhythmx.checkin.weekly"))
        XCTAssertEqual(center.request("rhythmx.insight.2026-10-21")?.content.body,
                       "Written on this phone. \(NotificationScheduler.insightLogNudge)")
        XCTAssertNotEqual(center.request("rhythmx.insight.2026-10-22")?.content.body,
                          "Written on this phone. \(NotificationScheduler.insightLogNudge)", "later days keep the template")
        XCTAssertEqual(reloads, 1)
    }

    func testAnOlderRunCannotAddRequestsAfterANewerRunReplacedThem() async {
        let center = GatedCenter()
        let held = expectation(description: "the older run is waiting in the center")
        center.onFirstWait = { held.fulfill() }
        let clock = at(20, 10)
        let notifier = DailyInsightsNotifier(center: center, writer: MarkingWriter(), cache: suite, calendar: calendar,
                                             now: { clock }, reloadWidgets: {})
        let older = Task { await notifier.schedule(self.input()) }
        await fulfillment(of: [held], timeout: 5)
        // The person turns Daily insights off while the older run is still going.
        let newer = Task { await notifier.schedule(self.input(DailyInsightsSetting(isOn: false, hour: 9, minute: 0, discreet: false))) }
        try? await Task.sleep(for: .milliseconds(200))
        center.open()
        await older.value
        await newer.value
        XCTAssertEqual(center.inner.insightIDs, [], "the newer run (off) wins")
    }

    func testScheduleKeepsTheWrittenNoteWithoutCallingTheWriterAgain() async {
        let center = FakeCenter()
        let writer = MarkingWriter()
        let notifier = notifier(center, writer: writer)
        await notifier.refresh(input())
        XCTAssertEqual(writer.calls, 1)

        await notifier.schedule(input())
        XCTAssertEqual(writer.calls, 1)
        XCTAssertEqual(center.request("rhythmx.insight.2026-10-21")?.content.body,
                       "Written on this phone. \(NotificationScheduler.insightLogNudge)")
    }

    func testRefreshWhenOffOrDeniedRemovesInsightRequests() async {
        let center = FakeCenter()
        center.pending = [FakeCenter.placeholder("rhythmx.insight.2026-10-21"), FakeCenter.placeholder("rhythmx.fertile.start")]
        let writer = MarkingWriter()
        await notifier(center, writer: writer).refresh(input(DailyInsightsSetting(isOn: false, hour: 9, minute: 0, discreet: false)))
        XCTAssertEqual(center.insightIDs, [])
        XCTAssertNotNil(center.request("rhythmx.fertile.start"))
        XCTAssertEqual(writer.calls, 0, "no writing while the setting is off")

        center.pending.append(FakeCenter.placeholder("rhythmx.insight.2026-10-22"))
        center.authorized = false
        await notifier(center, writer: writer).refresh(input())
        XCTAssertEqual(center.insightIDs, [])
        XCTAssertEqual(writer.calls, 0)
    }

    func testExpiredRefreshKeepsTheTemplateNotes() async {
        let center = FakeCenter()
        let writer = MarkingWriter()
        writer.cancelsCurrentTask = true
        var reloads = 0
        let notifier = notifier(center, writer: writer, reloaded: { reloads += 1 })
        await Task { await notifier.refresh(input()) }.value

        XCTAssertEqual(center.insightIDs.count, 7, "the template notes scheduled before writing stay")
        XCTAssertNotEqual(center.request("rhythmx.insight.2026-10-21")?.content.body,
                          "Written on this phone. \(NotificationScheduler.insightLogNudge)")
        XCTAssertEqual(reloads, 0)
    }

    func testDiscreetRefreshNeverPutsWrittenTextOnTheLockScreen() async {
        let center = FakeCenter()
        await notifier(center).refresh(input(DailyInsightsSetting(isOn: true, hour: 9, minute: 0, discreet: true)))
        XCTAssertEqual(center.request("rhythmx.insight.2026-10-21")?.content.body, "Your daily note is ready")
        XCTAssertEqual(center.request("rhythmx.insight.2026-10-21")?.content.title, "RhythmX")
    }

    func testInputLoadsTheStoresOnDiskData() throws {
        suite.set(try JSONEncoder().encode(cycleEvents), forKey: PersistenceKeys.events)
        suite.set("planning", forKey: "trackingMode")
        suite.set(true, forKey: AppSettings.dailyInsightsOnKey)
        let loaded = DailyInsightsInput.load(from: suite)
        XCTAssertEqual(loaded.events.count, cycleEvents.count)
        XCTAssertEqual(loaded.mode, .planning)
        XCTAssertTrue(loaded.setting.isOn)
        XCTAssertEqual(loaded.archivedBlocks.count, 0)
    }

    // MARK: - Service cache

    func testServiceCachedInsightsMatchOnlyTheSameDayAndFacts() async {
        let facts = InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 24)
        let service = DailyInsightsService(writer: MarkingWriter(), defaults: suite, now: { self.at(21, 9) },
                                           storageKey: "test.cache")
        XCTAssertNil(service.cachedInsights(for: facts))
        _ = await service.insights(for: facts)
        XCTAssertEqual(service.cachedInsights(for: facts)?.moodLine, "Written on this phone.")
        XCTAssertNil(service.cachedInsights(for: InsightFacts(mode: .cycle, phase: .luteal, cycleDay: 25)))
        XCTAssertNil(suite.data(forKey: DailyInsightsService.storageKey), "a custom key leaves the Today cache alone")

        let nextDay = DailyInsightsService(writer: MarkingWriter(), defaults: suite, now: { self.at(22, 9) },
                                           storageKey: "test.cache")
        XCTAssertNil(nextDay.cachedInsights(for: facts))
    }

    // MARK: - Background refresh timing

    func testBackgroundRefreshAsksForAboutThreeHoursBeforeTheNextNote() {
        XCTAssertEqual(DailyInsightsBackground.earliestBeginDate(setting: on, now: at(20, 10), calendar: calendar), at(21, 6))
        XCTAssertEqual(DailyInsightsBackground.earliestBeginDate(setting: on, now: at(20, 5), calendar: calendar), at(20, 6))
        XCTAssertEqual(DailyInsightsBackground.earliestBeginDate(setting: on, now: at(20, 7), calendar: calendar), at(21, 6),
                       "inside the window the next run is for tomorrow's note")
        XCTAssertNil(DailyInsightsBackground.earliestBeginDate(setting: DailyInsightsSetting(isOn: false, hour: 9, minute: 0, discreet: false),
                                                               now: at(20, 10), calendar: calendar))
    }

    func testBackgroundTaskIdentifierIsPermittedInInfoPlist() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary, "the host app's Info.plist")
        let permitted = info["BGTaskSchedulerPermittedIdentifiers"] as? [String] ?? []
        XCTAssertTrue(permitted.contains(DailyInsightsBackground.taskIdentifier), "\(permitted)")
        XCTAssertTrue((info["UIBackgroundModes"] as? [String] ?? []).contains("fetch"))
    }

    // MARK: - Tap routing

    func testQuickLogTapRoutesAndIsKeptForColdLaunch() {
        XCTAssertEqual(NotificationTapRouter.route(for: ["destination": "quickLog"])?.name, .rhythmxOpenQuickLog)

        let router = NotificationTapRouter()
        router.remember(userInfo: ["destination": "quickLog"])
        XCTAssertEqual(router.takePendingRoute()?.name, .rhythmxOpenQuickLog)
        XCTAssertNil(router.takePendingRoute())
    }

    func testWeeklyReviewRoutingIsUnchanged() {
        XCTAssertEqual(NotificationTapRouter.route(for: ["destination": "weeklyReview"])?.name, .rhythmxOpenPatterns)
        XCTAssertNil(NotificationTapRouter.route(for: [:]))
    }

    func testQuickLogRouteOpensTheModesMainCategory() {
        XCTAssertEqual(QuickLogRoute(mode: .cycle).category, .symptom)
        XCTAssertEqual(QuickLogRoute(mode: .planning).category, .planning)
        XCTAssertEqual(QuickLogRoute(mode: .menopause).category, .menopause)
    }

    // MARK: - Settings summary

    func testSettingsSummaryNamesTheFourGroups() {
        XCTAssertEqual(SettingsView.notificationsSummary(period: true, fertile: false, dailyInsights: true, weeklyReview: false),
                       "Period on. Fertile window off. Daily insights on. Weekly review off.")
    }

    // MARK: - Migration

    func testMigrationCancelsTagRemindersAndDailyCheckInOnce() async {
        let center = FakeCenter()
        center.pending = ["rhythmx.reminder.A0000000-0000-4000-8000-000000000001.2", "rhythmx.checkin.daily",
                          "rhythmx.checkin.daily.3", "rhythmx.checkin.weekly", "rhythmx.fertile.start", "rhythmx.cycle.dayof"]
            .map(FakeCenter.placeholder)
        suite.set(Data("[]".utf8), forKey: "loggingReminders")
        suite.set(Data("{}".utf8), forKey: "dailyCheckIn")
        suite.set(Data("{}".utf8), forKey: "weeklyCheckIn")

        await NotificationMigration.runIfNeeded(defaults: suite, center: center)

        XCTAssertEqual(center.pending.map(\.identifier).sorted(),
                       ["rhythmx.checkin.weekly", "rhythmx.cycle.dayof", "rhythmx.fertile.start"])
        XCTAssertNil(suite.object(forKey: "loggingReminders"))
        XCTAssertNil(suite.object(forKey: "dailyCheckIn"))
        XCTAssertNotNil(suite.object(forKey: "weeklyCheckIn"), "the weekly check-in stays")

        center.pending.append(FakeCenter.placeholder("rhythmx.reminder.late"))
        center.removed = []
        await NotificationMigration.runIfNeeded(defaults: suite, center: center)
        XCTAssertEqual(center.removed, [], "runs once")
    }

    // MARK: - Backup

    /// A backup written by an earlier 2.0 build, with tag reminders and a daily check-in.
    private func oldBackupData() throws -> Data {
        let settingsJSON: [String: Any] = [
            "phaseColors": ["#111111", "#222222", "#333333", "#444444"],
            "notificationsEnabled": false, "notifyDayBefore": true, "notifyDayOf": true,
            "fertileStartOn": false, "fertileOvulationOn": false,
            "trackingMode": "cycle", "defaultModeOnLaunch": "last", "themeID": "default",
            "reminders": [["id": "A0000000-0000-4000-8000-000000000001", "title": "Log symptoms", "hour": 21, "minute": 0,
                           "weekdays": [2], "category": "Symptom", "mode": "cycle", "isOn": true, "destination": "tagForm"]],
            "dailyCheckIn": ["isOn": true, "hour": 20, "minute": 0, "weekdays": []],
            "weeklyCheckIn": ["isOn": true, "hour": 18, "minute": 30, "weekdays": [1]]
        ]
        let body = try JSONSerialization.data(withJSONObject: ["events": [], "archivedBlocks": [], "settings": settingsJSON])
        return try JSONSerialization.data(withJSONObject: [
            "formatVersion": 1, "appVersion": "2.0.0", "createdAt": "2026-10-19T10:00:00Z",
            "encrypted": false, "body": body.base64EncodedString()
        ])
    }

    func testOldBackupWithRemindersOpensAndRestoresWithoutThem() throws {
        let keys = ["loggingReminders", "dailyCheckIn", "weeklyCheckIn", "notificationsEnabled"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) } }
        UserDefaults.standard.removeObject(forKey: "loggingReminders")
        UserDefaults.standard.removeObject(forKey: "dailyCheckIn")
        let settings = AppSettings()
        let before = settings.settingsSnapshot()
        defer { settings.apply(before) }

        let payload = try BackupFile.open(try oldBackupData(), passphrase: nil)
        XCTAssertNil(payload.settings.dailyInsightsOn, "an old file says nothing about Daily insights")
        settings.apply(payload.settings)

        XCTAssertNil(UserDefaults.standard.object(forKey: "loggingReminders"), "tag reminders are never re-created")
        XCTAssertNil(UserDefaults.standard.object(forKey: "dailyCheckIn"), "the daily check-in is never re-created")
        XCTAssertEqual(settings.weeklyCheckIn, CheckInSetting(isOn: true, hour: 18, minute: 30, weekdays: [1]))
    }

    func testNewBackupsCarryDailyInsightsAndNoReminders() throws {
        let settings = AppSettings()
        let before = settings.settingsSnapshot()
        defer { settings.apply(before) }
        settings.dailyInsightsOn = true
        settings.dailyInsightsHour = 20
        settings.dailyInsightsMinute = 30
        settings.dailyInsightsDiscreet = true

        let snapshot = settings.settingsSnapshot()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        XCTAssertNil(json["reminders"])
        XCTAssertNil(json["dailyCheckIn"])
        XCTAssertEqual(json["dailyInsightsOn"] as? Bool, true)
        XCTAssertEqual(json["dailyInsightsHour"] as? Int, 20)

        settings.dailyInsightsOn = false
        settings.dailyInsightsHour = 9
        settings.dailyInsightsDiscreet = false
        let data = try BackupFile.make(BackupPayload(events: [], archivedBlocks: [], settings: snapshot),
                                       appVersion: "2.0.0", passphrase: nil)
        settings.apply(try BackupFile.open(data, passphrase: nil).settings)
        XCTAssertTrue(settings.dailyInsightsOn)
        XCTAssertEqual(settings.dailyInsightsHour, 20)
        XCTAssertEqual(settings.dailyInsightsMinute, 30)
        XCTAssertTrue(settings.dailyInsightsDiscreet)
        XCTAssertEqual(BackupFile.currentFormat, 1)
    }
}
