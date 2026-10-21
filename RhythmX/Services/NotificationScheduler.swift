//  NotificationScheduler.swift

import UserNotifications
import Foundation

struct NotificationScheduler {

    // MARK: - Identifiers
    static let cycleIdentifiers = ["rhythmx.cycle.daybefore", "rhythmx.cycle.dayof"]
    static let fertileStartID = "rhythmx.fertile.start"
    static let fertileOvulationID = "rhythmx.fertile.ovulation"
    static let fertileIdentifiers = [fertileStartID, fertileOvulationID]
    static let checkInPrefix = "rhythmx.checkin."
    static let weeklyCheckInID = "rhythmx.checkin.weekly"

    /// `userInfo["destination"]`: where a tap leads.
    enum Destination: String {
        /// The Patterns view on the Tags tab (the weekly check-in).
        case weeklyReview
        /// The quick log (the Daily insights note).
        case quickLog
    }

    /// Period and fertile window reminders fire at this time.
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

    // MARK: - Lock Screen privacy

    /// Lock Screen privacy: with the switch on, every RhythmX notification (period, fertile window, weekly
    /// review and Daily insights) shows only this neutral text. Stored under the Daily insights key it started
    /// with (`AppSettings.dailyInsightsDiscreetKey`), so backups and earlier builds keep working.
    static let discreetTitle = "RhythmX"
    static let discreetReminderBody = "A reminder from RhythmX"

    /// The Lock Screen privacy switch as stored, for scheduling paths that have no AppSettings.
    static func isDiscreet(defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.bool(forKey: AppSettings.dailyInsightsDiscreetKey)
    }

    // MARK: - Period reminders

    static let periodTitle = "Cycle Reminder"
    static let periodDayBeforeBody = "Your cycle is anticipated to start tomorrow. Be prepared."
    static let periodDayOfBody = "Menstrual cycle is anticipated to start today."

    /// The period reminder's text; neutral with Lock Screen privacy on.
    static func periodContent(dayBefore: Bool, discreet: Bool) -> (title: String, body: String) {
        if discreet { return (discreetTitle, discreetReminderBody) }
        return (periodTitle, dayBefore ? periodDayBeforeBody : periodDayOfBody)
    }

    static func scheduleCycleReminders(for date: Date, dayBefore: Bool, dayOf: Bool, discreet: Bool = isDiscreet()) {
        cancelAllCycleReminders()

        if dayBefore, let dayBeforeDate = Calendar.current.date(byAdding: .day, value: -1, to: date) {
            let text = periodContent(dayBefore: true, discreet: discreet)
            schedule(
                id: "rhythmx.cycle.daybefore",
                title: text.title,
                body: text.body,
                date: dayBeforeDate
            )
        }

        if dayOf {
            let text = periodContent(dayBefore: false, discreet: discreet)
            schedule(
                id: "rhythmx.cycle.dayof",
                title: text.title,
                body: text.body,
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
    /// Neutral text with Lock Screen privacy on.
    static func fertileRequests(window: ClosedRange<Date>?, ovulation: Date?, startOn: Bool, ovulationOn: Bool,
                                mode: TrackingMode, now: Date = Date(),
                                calendar: Calendar = .current, discreet: Bool = false) -> [UNNotificationRequest] {
        guard mode != .menopause else { return [] }
        var requests: [UNNotificationRequest] = []

        if startOn, let start = window?.lowerBound,
           let request = oneOffRequest(id: fertileStartID,
                                       title: discreet ? discreetTitle : "Fertile window",
                                       body: discreet ? discreetReminderBody
                                           : "Your fertile window is estimated to start today. Estimates only.",
                                       date: start, now: now, calendar: calendar) {
            requests.append(request)
        }
        if ovulationOn, let ovulation,
           let request = oneOffRequest(id: fertileOvulationID,
                                       title: discreet ? discreetTitle : "Likely ovulation",
                                       body: discreet ? discreetReminderBody
                                           : "Today is your likely ovulation day. Estimates only.",
                                       date: ovulation, now: now, calendar: calendar) {
            requests.append(request)
        }
        return requests
    }

    /// Cancels both fertile identifiers, then adds whatever `fertileRequests` returns.
    static func scheduleFertileReminders(window: ClosedRange<Date>?, ovulation: Date?, startOn: Bool,
                                         ovulationOn: Bool, mode: TrackingMode, discreet: Bool = isDiscreet()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: fertileIdentifiers)
        for request in fertileRequests(window: window, ovulation: ovulation, startOn: startOn,
                                       ovulationOn: ovulationOn, mode: mode, discreet: discreet) {
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

    // MARK: - Weekly review check-in

    /// Pure: the weekly review check-in, exactly one repeating request that opens the Patterns view.
    /// Neutral text with Lock Screen privacy on.
    static func checkInRequests(weekly: CheckInSetting?, discreet: Bool = false) -> [UNNotificationRequest] {
        guard let weekly, weekly.isOn else { return [] }
        return [repeatingRequest(id: weeklyCheckInID, title: discreet ? discreetTitle : "Weekly check-in",
                                 body: discreet ? discreetReminderBody : "Take a look at your patterns from this week.",
                                 hour: weekly.hour, minute: weekly.minute, weekday: weekly.singleWeekday,
                                 userInfo: ["destination": Destination.weeklyReview.rawValue])]
    }

    /// Cancels every `rhythmx.checkin.` request (which also clears any daily check-in left by an earlier build),
    /// then adds the weekly one.
    static func scheduleCheckIns(weekly: CheckInSetting?, discreet: Bool = isDiscreet()) {
        replace(prefix: checkInPrefix, with: checkInRequests(weekly: weekly, discreet: discreet))
    }

    // MARK: - Daily insights

    static let insightPrefix = "rhythmx.insight."
    /// The gentle nudge after the day's insight.
    static let insightLogNudge = "Tap to log how today feels."
    /// Lock Screen privacy: no cycle details at all.
    static let discreetInsightTitle = discreetTitle
    static let discreetInsightBody = "Your daily note is ready"

    /// "rhythmx.insight.2026-10-21" for the note on that day.
    static func insightIdentifier(for day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return insightPrefix + String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The Lock Screen text for a day's insights.
    static func insightContent(_ insights: DailyInsights, discreet: Bool) -> (title: String, body: String) {
        if discreet { return (discreetInsightTitle, discreetInsightBody) }
        return (insights.notificationTitle, "\(insights.notificationBody) \(insightLogNudge)")
    }

    /// Pure: one non-repeating request for each of the next `days` notes at the chosen time, never at or before
    /// `now`. Each carries that day's note for the current mode: `written` when it has one for the day's facts,
    /// else the template's. A tap opens the quick log. Nothing when the setting is off or not authorized.
    static func dailyInsightRequests(setting: DailyInsightsSetting, authorized: Bool, mode: TrackingMode,
                                     events: [Event], archivedBlocks: [ArchivedDataBlock], overrides: FertileOverrides,
                                     now: Date = Date(), calendar: Calendar = .current, days: Int = 7,
                                     written: (Date, InsightFacts) -> DailyInsights? = { _, _ in nil }) -> [UNNotificationRequest] {
        guard setting.isOn, authorized else { return [] }
        let template = TemplateInsightWriter()
        return setting.fireDates(after: now, count: days, calendar: calendar).map { fire in
            let facts = InsightFacts.make(events: events, archivedBlocks: archivedBlocks, mode: mode, today: fire,
                                          fertileOverrides: overrides, calendar: calendar)
            let insights = written(fire, facts) ?? template.insights(for: facts)
            let text = insightContent(insights, discreet: setting.discreet)

            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            content.userInfo = ["destination": Destination.quickLog.rawValue]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return UNNotificationRequest(identifier: insightIdentifier(for: fire, calendar: calendar),
                                         content: content, trigger: trigger)
        }
    }

    // MARK: - Everything at once

    /// Reschedules the fertile window, the weekly check-in and the Daily insights notes from the current
    /// state. Called where period reminders are rescheduled: settings changes, event changes and mode changes.
    @MainActor
    static func rescheduleAll(events: [Event], overrides: FertileOverrides, settings: AppSettings) {
        let mode = settings.trackingMode
        let dates = fertileDates(events: events, overrides: overrides)
        scheduleFertileReminders(window: dates.window, ovulation: dates.ovulation,
                                 startOn: settings.fertileStartOn, ovulationOn: settings.fertileOvulationOn, mode: mode)
        scheduleCheckIns(weekly: settings.weeklyCheckIn)
        DailyInsightsCoordinator.shared.update(write: false)
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
    /// Opens the quick log (`QuickLogRoute`) for the current mode.
    static let rhythmxOpenQuickLog = Notification.Name("rhythmxOpenQuickLog")
}

/// Turns a notification tap into an in-app `Notification.Name` post, which the tab view handles.
/// Period and fertile window reminders carry no userInfo and simply open the app, as before.
final class NotificationTapRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTapRouter()

    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    /// The in-app notification for a tap, or nil when the tap just opens the app.
    static func route(for userInfo: [AnyHashable: Any]) -> (name: Notification.Name, userInfo: [String: String])? {
        switch userInfo["destination"] as? String {
        case NotificationScheduler.Destination.weeklyReview.rawValue?:
            return (.rhythmxOpenPatterns, [:])
        case NotificationScheduler.Destination.quickLog.rawValue?:
            return (.rhythmxOpenQuickLog, [:])
        default:
            break
        }
        // Tag reminders and daily check-ins from earlier 2.0 builds carried a category; one still in
        // Notification Center opens the tag form on it.
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
