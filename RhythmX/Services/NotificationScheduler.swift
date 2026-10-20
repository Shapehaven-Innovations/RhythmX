//  NotificationScheduler.swift

import UserNotifications
import Foundation

struct NotificationScheduler {

    // MARK: - Identifiers
    static let cycleIdentifiers = ["rhythmx.cycle.daybefore", "rhythmx.cycle.dayof"]
    static let fertileStartID = "rhythmx.fertile.start"
    static let fertileOvulationID = "rhythmx.fertile.ovulation"
    static let fertileIdentifiers = [fertileStartID, fertileOvulationID]
    static let reminderPrefix = "rhythmx.reminder."
    static let checkInPrefix = "rhythmx.checkin."
    static let dailyCheckInID = "rhythmx.checkin.daily"
    static let weeklyCheckInID = "rhythmx.checkin.weekly"

    /// Every reminder fires at this time unless the user picked one.
    static let morningHour = 8

    static func requestPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                ) { granted, _ in
                    DispatchQueue.main.async { completion(granted) }
                }
            case .authorized, .provisional:
                DispatchQueue.main.async { completion(true) }
            default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    // MARK: - Period reminders (unchanged)

    static func scheduleCycleReminders(for date: Date, dayBefore: Bool, dayOf: Bool) {
        cancelAllCycleReminders()

        if dayBefore, let dayBeforeDate = Calendar.current.date(byAdding: .day, value: -1, to: date) {
            schedule(
                id: "rhythmx.cycle.daybefore",
                title: "Cycle Reminder",
                body: "Your cycle is anticipated to start tomorrow. Be prepared.",
                date: dayBeforeDate
            )
        }

        if dayOf {
            schedule(
                id: "rhythmx.cycle.dayof",
                title: "Cycle Reminder",
                body: "Menstrual cycle is anticipated to start today.",
                date: date
            )
        }
    }

    static func cancelAllCycleReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [
                "rhythmx.cycle.daybefore",
                "rhythmx.cycle.dayof"
            ])
    }

    private static func schedule(id: String, title: String, body: String, date: Date) {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 8
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Fertile window reminders

    /// The estimated window and likely ovulation day from `FertileWindow` on cycle events.
    /// Menopause entries are dropped here as well, so a caller passing every event gets the same answer.
    static func fertileDates(events: [Event], overrides: FertileOverrides, today: Date = Date(),
                             calendar: Calendar = .current) -> (window: ClosedRange<Date>?, ovulation: Date?) {
        let insights = PlanningInsights.make(events: events.filter { $0.effectiveMode != .menopause },
                                             overrides: overrides, today: today, calendar: calendar)
        return (insights.fertileWindow, insights.likelyOvulation)
    }

    /// Pure: the requests for the fertile window. Nothing in Menopause mode, nothing at or before `now`.
    static func fertileRequests(window: ClosedRange<Date>?, ovulation: Date?, startOn: Bool, ovulationOn: Bool,
                                mode: TrackingMode, now: Date = Date(),
                                calendar: Calendar = .current) -> [UNNotificationRequest] {
        guard mode != .menopause else { return [] }
        var requests: [UNNotificationRequest] = []

        if startOn, let start = window?.lowerBound,
           let request = oneOffRequest(id: fertileStartID,
                                       title: "Fertile window",
                                       body: "Your fertile window is estimated to start today. Estimates only.",
                                       date: start, now: now, calendar: calendar) {
            requests.append(request)
        }
        if ovulationOn, let ovulation,
           let request = oneOffRequest(id: fertileOvulationID,
                                       title: "Likely ovulation",
                                       body: "Today is your likely ovulation day. Estimates only.",
                                       date: ovulation, now: now, calendar: calendar) {
            requests.append(request)
        }
        return requests
    }

    /// Cancels both fertile identifiers, then adds whatever `fertileRequests` returns.
    static func scheduleFertileReminders(window: ClosedRange<Date>?, ovulation: Date?, startOn: Bool,
                                         ovulationOn: Bool, mode: TrackingMode) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: fertileIdentifiers)
        for request in fertileRequests(window: window, ovulation: ovulation, startOn: startOn,
                                       ovulationOn: ovulationOn, mode: mode) {
            center.add(request)
        }
    }

    /// A non-repeating request at 8:00 on `date`'s day, or nil when that moment is not after `now`.
    private static func oneOffRequest(id: String, title: String, body: String, date: Date, now: Date,
                                      calendar: Calendar) -> UNNotificationRequest? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = morningHour
        components.minute = 0
        guard let fireDate = calendar.date(from: components), fireDate > now else { return nil }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    // MARK: - Check-ins

    /// Pure: the daily check-in (one request per selected weekday, or one every-day request) and the
    /// weekly check-in (exactly one request). The daily one opens the tag form on the mode's main
    /// category; the weekly one opens the Patterns view.
    static func checkInRequests(daily: CheckInSetting?, weekly: CheckInSetting?, mode: TrackingMode) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []

        if let daily, daily.isOn {
            let userInfo: [String: String] = [
                "category": mode.mainCategory.rawValue,
                "destination": LoggingReminder.Destination.tagForm.rawValue
            ]
            if daily.weekdays.isEmpty {
                requests.append(repeatingRequest(id: dailyCheckInID, title: "Daily check-in",
                                                 body: "How are you feeling today? Tap to log a tag.",
                                                 hour: daily.hour, minute: daily.minute, weekday: nil, userInfo: userInfo))
            } else {
                for weekday in daily.weekdays.sorted() {
                    requests.append(repeatingRequest(id: "\(dailyCheckInID).\(weekday)", title: "Daily check-in",
                                                     body: "How are you feeling today? Tap to log a tag.",
                                                     hour: daily.hour, minute: daily.minute, weekday: weekday, userInfo: userInfo))
                }
            }
        }

        if let weekly, weekly.isOn {
            requests.append(repeatingRequest(id: weeklyCheckInID, title: "Weekly check-in",
                                             body: "Take a look at your patterns from this week.",
                                             hour: weekly.hour, minute: weekly.minute, weekday: weekly.singleWeekday,
                                             userInfo: ["destination": LoggingReminder.Destination.weeklyReview.rawValue]))
        }
        return requests
    }

    /// Cancels every `rhythmx.checkin.` request, then adds the current ones.
    static func scheduleCheckIns(daily: CheckInSetting?, weekly: CheckInSetting?, mode: TrackingMode) {
        let requests = checkInRequests(daily: daily, weekly: weekly, mode: mode)
        replace(prefix: checkInPrefix, with: requests)
    }

    // MARK: - Tag reminders

    /// Pure: one repeating request per weekday for each reminder that is on and belongs to `activeMode`.
    static func requests(for reminders: [LoggingReminder], activeMode: TrackingMode) -> [UNNotificationRequest] {
        reminders
            .filter { $0.isOn && $0.mode == activeMode }
            .flatMap { reminder -> [UNNotificationRequest] in
                let weekdays = reminder.weekdays.isEmpty ? Array(1...7) : reminder.weekdays.sorted()
                let userInfo = [
                    "category": reminder.category.rawValue,
                    "destination": reminder.destination.rawValue
                ]
                return weekdays.map { weekday in
                    repeatingRequest(id: "\(reminderPrefix)\(reminder.id.uuidString).\(weekday)",
                                     title: reminder.title,
                                     body: reminder.destination == .weeklyReview
                                        ? "Take a look at your patterns."
                                        : "Tap to log in \(reminder.category.rawValue).",
                                     hour: reminder.hour, minute: reminder.minute, weekday: weekday, userInfo: userInfo)
                }
            }
    }

    /// Cancels every `rhythmx.reminder.` request, then adds the current mode's reminders.
    static func scheduleLoggingReminders(_ reminders: [LoggingReminder], activeMode: TrackingMode) {
        replace(prefix: reminderPrefix, with: requests(for: reminders, activeMode: activeMode))
    }

    // MARK: - Everything at once

    /// Reschedules the fertile window, check-in and tag reminders from the current state. Called where
    /// period reminders are rescheduled: settings changes, event changes and mode changes.
    static func rescheduleAll(events: [Event], overrides: FertileOverrides, settings: AppSettings,
                              reminders: [LoggingReminder] = ReminderStore.load()) {
        let mode = settings.trackingMode
        let dates = fertileDates(events: events, overrides: overrides)
        scheduleFertileReminders(window: dates.window, ovulation: dates.ovulation,
                                 startOn: settings.fertileStartOn, ovulationOn: settings.fertileOvulationOn, mode: mode)
        scheduleCheckIns(daily: settings.dailyCheckIn, weekly: settings.weeklyCheckIn, mode: mode)
        scheduleLoggingReminders(reminders, activeMode: mode)
    }

    // MARK: - Helpers

    private static func repeatingRequest(id: String, title: String, body: String, hour: Int, minute: Int,
                                         weekday: Int?, userInfo: [String: String]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.weekday = weekday
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// Removes every pending request whose identifier starts with `prefix`, then adds `requests`.
    private static func replace(prefix: String, with requests: [UNNotificationRequest]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for request in requests { center.add(request) }
        }
    }
}

// MARK: - Tap routing

extension Notification.Name {
    /// userInfo["category"] holds a `TagCategory` raw value.
    static let rhythmxOpenTagForm = Notification.Name("rhythmxOpenTagForm")
    /// Opens the Tags tab with the Patterns segment.
    static let rhythmxOpenPatterns = Notification.Name("rhythmxOpenPatterns")
}

/// Turns a notification tap into an in-app `Notification.Name` post, which the tab view handles.
/// Period reminders carry no userInfo and simply open the app, as before.
final class NotificationTapRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTapRouter()

    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    /// The in-app notification for a tap, or nil when the tap just opens the app.
    static func route(for userInfo: [AnyHashable: Any]) -> (name: Notification.Name, userInfo: [String: String])? {
        if userInfo["destination"] as? String == LoggingReminder.Destination.weeklyReview.rawValue {
            return (.rhythmxOpenPatterns, [:])
        }
        if let raw = userInfo["category"] as? String, TagCategory(rawValue: raw) != nil {
            return (.rhythmxOpenTagForm, ["category": raw])
        }
        return nil
    }

    /// The last tap the tab view has not handled yet. A tap that launches the app arrives before
    /// `StartTabView` subscribes to the posts, so the view also reads this when it appears. Main thread only.
    private var pendingRoute: (name: Notification.Name, userInfo: [String: String])?

    /// Keeps the tap's route for `takePendingRoute()` and posts it for a tab view already on screen.
    /// Taps with no route (period reminders) keep nothing.
    func remember(userInfo: [AnyHashable: Any]) {
        guard let route = Self.route(for: userInfo) else { return }
        pendingRoute = route
        NotificationCenter.default.post(name: route.name, object: nil, userInfo: route.userInfo)
    }

    /// The kept route, once. Nil when there is none or it was already taken.
    func takePendingRoute() -> (name: Notification.Name, userInfo: [String: String])? {
        defer { pendingRoute = nil }
        return pendingRoute
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        DispatchQueue.main.async { self.remember(userInfo: userInfo) }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
