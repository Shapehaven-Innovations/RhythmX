//  NotificationsPage.swift
//  The pure parts of the Notifications page: each group's one-line summary and the Lock Screen preview of
//  what will actually arrive. The preview uses the same text the scheduler sends.

import Foundation

enum NotificationsPage {
    /// Always visible under the groups. The birth control line sits in the Fertile window card itself.
    static let footer = "Notifications are scheduled on this iPhone. Nothing leaves this device."

    // MARK: - Time

    /// "8:00 PM" in the user's time format.
    static func time(hour: Int, minute: Int, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour, minute: minute)) ?? Date()
        return clean(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                                     calendar: calendar, timeZone: calendar.timeZone)))
    }

    /// "8:00 PM" for today, "Thu 8:00 AM" for another day.
    static func whenLabel(_ date: Date, now: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let clock = time(hour: parts.hour ?? 0, minute: parts.minute ?? 0, locale: locale, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) { return clock }
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
        style = style.weekday(.abbreviated)
        return "\(date.formatted(style)) \(clock)"
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func morning(_ locale: Locale) -> String {
        time(hour: NotificationScheduler.morningHour, minute: 0, locale: locale)
    }

    // MARK: - Summaries

    static func periodSummary(on: Bool, dayBefore: Bool, dayOf: Bool, locale: Locale = .current) -> String {
        guard on else { return "Off" }
        switch (dayBefore, dayOf) {
        case (true, true):   return "Day before and day of, at \(morning(locale))"
        case (true, false):  return "The day before, at \(morning(locale))"
        case (false, true):  return "On the day, at \(morning(locale))"
        case (false, false): return "On, but no day is picked"
        }
    }

    static func fertileSummary(startOn: Bool, ovulationOn: Bool, mode: TrackingMode, locale: Locale = .current) -> String {
        if mode == .menopause { return "Not scheduled in Menopause mode" }
        switch (startOn, ovulationOn) {
        case (true, true):   return "Window start and likely ovulation, at \(morning(locale))"
        case (true, false):  return "When the window starts, at \(morning(locale))"
        case (false, true):  return "Likely ovulation day, at \(morning(locale))"
        case (false, false): return "Off"
        }
    }

    static func dailyInsightsSummary(on: Bool, hour: Int, minute: Int, locale: Locale = .current) -> String {
        on ? "\(time(hour: hour, minute: minute, locale: locale)), opens a quick log" : "Off"
    }

    static func discreetSummary(on: Bool) -> String {
        on ? "Every notification hides its details" : "Notifications show details when locked"
    }

    static func weeklySummary(_ setting: CheckInSetting?, locale: Locale = .current,
                              calendar: Calendar = .current) -> String {
        guard let setting, setting.isOn else { return "Off" }
        var named = calendar
        named.locale = locale
        let day = named.weekdaySymbols[setting.singleWeekday - 1]
        return "Every \(day) at \(time(hour: setting.hour, minute: setting.minute, locale: locale, calendar: calendar))"
    }

    /// "3 on" in Settings.
    static func onCount(period: Bool, fertile: Bool, dailyInsights: Bool, weeklyReview: Bool) -> Int {
        [period, fertile, dailyInsights, weeklyReview].filter { $0 }.count
    }

    // MARK: - Preview

    struct Preview: Equatable {
        let title: String
        let body: String
    }

    /// The Daily insights note as the Lock Screen shows it, discreet text included.
    static func insightPreview(_ insights: DailyInsights, discreet: Bool) -> Preview {
        let text = NotificationScheduler.insightContent(insights, discreet: discreet)
        return Preview(title: text.title, body: text.body)
    }

    struct PeriodPreview: Equatable {
        let title: String
        let body: String
        let fire: Date
    }

    /// The next period reminder still to come, with the scheduler's text; nil when none is.
    static func periodPreview(predicted: Date?, dayBefore: Bool, dayOf: Bool, now: Date,
                              calendar: Calendar = .current, discreet: Bool = false) -> PeriodPreview? {
        guard let predicted else { return nil }
        let day = calendar.startOfDay(for: predicted)
        var candidates: [(Date, Bool)] = []
        if dayBefore, let before = calendar.date(byAdding: .day, value: -1, to: day) {
            candidates.append((before, true))
        }
        if dayOf { candidates.append((day, false)) }
        for (date, isDayBefore) in candidates {
            guard let fire = calendar.date(bySettingHour: NotificationScheduler.morningHour, minute: 0, second: 0, of: date),
                  fire > now else { continue }
            let text = NotificationScheduler.periodContent(dayBefore: isDayBefore, discreet: discreet)
            return PeriodPreview(title: text.title, body: text.body, fire: fire)
        }
        return nil
    }
}
