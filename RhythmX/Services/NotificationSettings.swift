//  NotificationSettings.swift
//  The typed settings behind the Notifications page (the weekly review check-in and Daily insights), where a
//  notification tap leads, and the one-time cleanup of the tag reminders and daily check-in that 2.0 replaced
//  with Daily insights. Scheduling lives in NotificationScheduler and DailyInsightsNotifier.

import Foundation
import UserNotifications

/// The weekly review check-in: one weekday and a time. Kept as JSON in `AppSettings.weeklyCheckInData`.
struct CheckInSetting: Codable, Equatable {
    var isOn: Bool
    var hour: Int
    var minute: Int
    var weekdays: Set<Int>

    static let defaultWeekly = CheckInSetting(isOn: false, hour: 18, minute: 0, weekdays: [1])

    /// The one weekday a weekly check-in fires on. Sunday when none is set.
    var singleWeekday: Int { weekdays.sorted().first ?? 1 }
}

// AppSettings.swift is also compiled by the widget target, which has no CheckInSetting, so the typed
// accessor lives here and AppSettings keeps the raw JSON.
extension AppSettings {
    var weeklyCheckIn: CheckInSetting? {
        get { weeklyCheckInData.flatMap { try? JSONDecoder().decode(CheckInSetting.self, from: $0) } }
        set { weeklyCheckInData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// The Daily insights setting as one value.
    var dailyInsights: DailyInsightsSetting {
        DailyInsightsSetting(isOn: dailyInsightsOn, hour: dailyInsightsHour, minute: dailyInsightsMinute,
                             discreet: dailyInsightsDiscreet)
    }
}

/// Daily insights: one note a day at a chosen time, with that day's insight and a nudge to log a tag.
/// Off by default. With `discreet` on, the Lock Screen shows only neutral text.
struct DailyInsightsSetting: Equatable {
    var isOn: Bool
    var hour: Int
    var minute: Int
    var discreet: Bool

    static let defaultHour = 9
    static let defaultMinute = 0

    /// Reads the plain keys `AppSettings` writes, with the same defaults, from any store (the background
    /// refresh has no AppSettings or UI).
    static func load(from defaults: UserDefaults = AppGroup.defaults) -> DailyInsightsSetting {
        DailyInsightsSetting(
            isOn: defaults.object(forKey: AppSettings.dailyInsightsOnKey) as? Bool ?? false,
            hour: defaults.object(forKey: AppSettings.dailyInsightsHourKey) as? Int ?? defaultHour,
            minute: defaults.object(forKey: AppSettings.dailyInsightsMinuteKey) as? Int ?? defaultMinute,
            discreet: defaults.object(forKey: AppSettings.dailyInsightsDiscreetKey) as? Bool ?? false
        )
    }

    /// The next `count` moments at the chosen time strictly after `now`, earliest first.
    func fireDates(after now: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0...count).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }
        .filter { $0 > now }
        .prefix(count)
        .map { $0 }
    }

    func nextFireDate(after now: Date, calendar: Calendar = .current) -> Date? {
        fireDates(after: now, count: 1, calendar: calendar).first
    }
}

extension TrackingMode {
    /// The category the quick log card's "More tags" opens the tag form on.
    var mainCategory: TagCategory {
        switch self {
        case .cycle:     return .symptom
        case .planning:  return .planning
        case .menopause: return .menopause
        }
    }
}

/// Where a tapped Daily insights note leads: the quick log card (QuickLogCardView). Its "More tags" opens the
/// Add Tags sheet on the mode's main category.
struct QuickLogRoute: Identifiable, Equatable {
    let mode: TrackingMode
    var category: TagCategory { mode.mainCategory }
    var id: String { mode.rawValue }
}

// MARK: - Notification center

/// The parts of `UNUserNotificationCenter` the Daily insights notifier and the migration use, so tests can
/// stand in for it.
protocol InsightNotificationCenter: AnyObject {
    func isAuthorizedForInsights() async -> Bool
    func pendingIdentifiers() async -> [String]
    func removePending(_ identifiers: [String])
    func addRequest(_ request: UNNotificationRequest) async
}

extension UNUserNotificationCenter: InsightNotificationCenter {
    func isAuthorizedForInsights() async -> Bool {
        switch await notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func pendingIdentifiers() async -> [String] {
        await pendingNotificationRequests().map(\.identifier)
    }

    func removePending(_ identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func addRequest(_ request: UNNotificationRequest) async {
        try? await add(request)
    }
}

// MARK: - Migration

/// Runs once on the first launch of the build that replaced tag reminders and the daily check-in with Daily
/// insights: cancels their pending requests and deletes their stored settings. The weekly check-in stays.
enum NotificationMigration {
    static let flagKey = "notificationsMigrationDailyInsightsV1"
    static let removedPrefixes = ["rhythmx.reminder.", "rhythmx.checkin.daily"]
    /// `ReminderStore.key` and the daily check-in JSON, both in the standard store.
    static let removedKeys = ["loggingReminders", "dailyCheckIn"]

    static func runIfNeeded(defaults: UserDefaults = .standard,
                            center: InsightNotificationCenter = UNUserNotificationCenter.current()) async {
        guard !defaults.bool(forKey: flagKey) else { return }
        let stale = await center.pendingIdentifiers().filter { id in removedPrefixes.contains { id.hasPrefix($0) } }
        if !stale.isEmpty { center.removePending(stale) }
        for key in removedKeys { defaults.removeObject(forKey: key) }
        defaults.set(true, forKey: flagKey)
    }
}
