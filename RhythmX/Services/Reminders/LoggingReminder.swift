//  LoggingReminder.swift
//  Tag reminders and check-in settings: the data behind the Notifications section in Settings.
//  Pure models plus their UserDefaults storage. Scheduling lives in NotificationScheduler.

import Foundation

/// One custom tag reminder. It belongs to a mode: only the current mode's reminders are scheduled,
/// the others stay saved and come back when the mode does.
struct LoggingReminder: Codable, Identifiable, Equatable {
    enum Destination: String, Codable {
        /// Opens the tag form on `category`.
        case tagForm
        /// Opens the Patterns view on the Tags tab.
        case weeklyReview
    }

    var id: UUID
    var title: String
    var hour: Int
    var minute: Int
    /// 1 = Sunday ... 7 = Saturday. Empty means every day.
    var weekdays: Set<Int>
    var category: TagCategory
    var mode: TrackingMode
    var isOn: Bool
    var destination: Destination

    /// The title as shown and spoken: the category name when the user left the title blank.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? category.rawValue : trimmed
    }

    init(id: UUID = UUID(), title: String, hour: Int, minute: Int, weekdays: Set<Int> = [],
         category: TagCategory, mode: TrackingMode, isOn: Bool = false, destination: Destination = .tagForm) {
        self.id = id
        self.title = title
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.category = category
        self.mode = mode
        self.isOn = isOn
        self.destination = destination
    }

    /// The reminders a fresh install starts with, all off. Fixed ids so the list is stable until the user edits it.
    static let defaults: [LoggingReminder] = [
        LoggingReminder(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!,
                        title: "Log symptoms", hour: 21, minute: 0, category: .symptom, mode: .cycle),
        LoggingReminder(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!,
                        title: "Log temperature", hour: 7, minute: 0, category: .basalTemp, mode: .planning),
        LoggingReminder(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!,
                        title: "Ovulation test", hour: 12, minute: 0, category: .planning, mode: .planning),
        LoggingReminder(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000004")!,
                        title: "Night sweats and sleep", hour: 7, minute: 30, category: .menopause, mode: .menopause),
        LoggingReminder(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000005")!,
                        title: "Log symptoms", hour: 21, minute: 0, category: .menopause, mode: .menopause)
    ]
}

/// The daily or weekly check-in. The daily check-in may use any set of weekdays (empty means every day);
/// the weekly check-in uses exactly one.
struct CheckInSetting: Codable, Equatable {
    var isOn: Bool
    var hour: Int
    var minute: Int
    var weekdays: Set<Int>

    static let defaultDaily = CheckInSetting(isOn: false, hour: 20, minute: 0, weekdays: [])
    static let defaultWeekly = CheckInSetting(isOn: false, hour: 18, minute: 0, weekdays: [1])

    /// The one weekday a weekly check-in fires on. Sunday when none is set.
    var singleWeekday: Int { weekdays.sorted().first ?? 1 }
}

/// Stores the tag reminders under one key. With nothing stored, the defaults (all off) are returned.
enum ReminderStore {
    static let key = "loggingReminders"

    static func load(defaults: UserDefaults = .standard) -> [LoggingReminder] {
        guard let data = defaults.data(forKey: key) else { return LoggingReminder.defaults }
        return (try? JSONDecoder().decode([LoggingReminder].self, from: data)) ?? LoggingReminder.defaults
    }

    static func save(_ reminders: [LoggingReminder], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        defaults.set(data, forKey: key)
    }
}

extension TrackingMode {
    /// The category the daily check-in opens the tag form on.
    var mainCategory: TagCategory {
        switch self {
        case .cycle:     return .symptom
        case .planning:  return .planning
        case .menopause: return .menopause
        }
    }
}

// AppSettings.swift is also compiled by the widget target, which has no CheckInSetting, so the typed
// accessors live here and AppSettings keeps the raw JSON.
extension AppSettings {
    var dailyCheckIn: CheckInSetting? {
        get { Self.decodeCheckIn(dailyCheckInData) }
        set { dailyCheckInData = Self.encodeCheckIn(newValue) }
    }

    var weeklyCheckIn: CheckInSetting? {
        get { Self.decodeCheckIn(weeklyCheckInData) }
        set { weeklyCheckInData = Self.encodeCheckIn(newValue) }
    }

    private static func decodeCheckIn(_ data: Data?) -> CheckInSetting? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CheckInSetting.self, from: data)
    }

    private static func encodeCheckIn(_ setting: CheckInSetting?) -> Data? {
        guard let setting else { return nil }
        return try? JSONEncoder().encode(setting)
    }
}
