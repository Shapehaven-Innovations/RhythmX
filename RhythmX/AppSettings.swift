//  AppSettings.swift

import SwiftUI

final class AppSettings: ObservableObject {
    /// The four phase colors are fixed (menstrual, follicular, ovulation, luteal), the same in every theme.
    /// 1.9.x let the user pick their own; those values may still sit under the `phaseColor1`...`phaseColor4`
    /// keys in the shared store, but nothing reads them any more. Backups write these defaults.
    static let phaseColorHexes = ["#C97C7C", "#7CA68C", "#C9A87C", "#8C7CA6"]

    // Notifications
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false
    @AppStorage("notifyDayBefore")      var notifyDayBefore: Bool = true
    @AppStorage("notifyDayOf")          var notifyDayOf: Bool = true

    // Fertile window reminders (Cycle and Planning only; never scheduled in Menopause). Off by default.
    @AppStorage("fertileStartOn")     var fertileStartOn: Bool = false
    @AppStorage("fertileOvulationOn") var fertileOvulationOn: Bool = false

    // Weekly review check-in, kept as JSON (`CheckInSetting`) so this file still compiles in the widget target,
    // which has no notification types. The typed accessor is in NotificationSettings.swift.
    @AppStorage("weeklyCheckIn") var weeklyCheckInData: Data?

    // Daily insights: one note a day at the chosen time (off by default). Plain values in the shared store so
    // the background refresh reads them without AppSettings (`DailyInsightsSetting.load`). The discreet key is
    // Lock Screen privacy: when on, every RhythmX notification (period, fertile window, weekly review and
    // Daily insights) shows only neutral text. It keeps its first name so backups and earlier builds still match.
    static let dailyInsightsOnKey = "dailyInsightsOn"
    static let dailyInsightsHourKey = "dailyInsightsHour"
    static let dailyInsightsMinuteKey = "dailyInsightsMinute"
    static let dailyInsightsDiscreetKey = "dailyInsightsDiscreet"
    @AppStorage(AppSettings.dailyInsightsOnKey, store: AppGroup.defaults)       var dailyInsightsOn: Bool = false
    @AppStorage(AppSettings.dailyInsightsHourKey, store: AppGroup.defaults)     var dailyInsightsHour: Int = 9
    @AppStorage(AppSettings.dailyInsightsMinuteKey, store: AppGroup.defaults)   var dailyInsightsMinute: Int = 0
    @AppStorage(AppSettings.dailyInsightsDiscreetKey, store: AppGroup.defaults) var dailyInsightsDiscreet: Bool = false

    // Apple Health (free). All off by default; each asks for its own Health permission when switched on.
    // Plain Bools so this file still compiles in the widget target, which has no HealthKit.
    @AppStorage("healthWritePeriod")     var healthWritePeriod: Bool = false
    @AppStorage("healthReadTemperature") var healthReadTemperature: Bool = false
    @AppStorage("healthReadSleep")       var healthReadSleep: Bool = false

    // Apple Calendar sync (Plus). Off by default. When Plus is no longer active the app removes its events and
    // turns the switch off (`CalendarSyncPolicy`). The typed `SyncOptions` and `DiscreetSymbols` accessors are in
    // CalendarSync.swift (app target only).
    @AppStorage("calendarSyncOn")              var calendarSyncOn: Bool = false
    @AppStorage("calendarSyncDiscreet")        var calendarSyncDiscreet: Bool = false
    @AppStorage("calendarSyncPeriodDays")      var calendarSyncPeriodDays: Bool = true
    @AppStorage("calendarSyncPredictedPeriod") var calendarSyncPredictedPeriod: Bool = true
    @AppStorage("calendarSyncFertileWindow")   var calendarSyncFertileWindow: Bool = true
    @AppStorage("calendarSyncPhaseStarts")     var calendarSyncPhaseStarts: Bool = true
    /// Set when the app's calendar events must go (a confirmed lapse, or the switch turned off) and cleared only
    /// once a removal succeeds, so a failed or access-blocked removal is retried on the next reconcile.
    @AppStorage("calendarSyncPendingRemoval")  var calendarSyncPendingRemoval: Bool = false
    // Discreet title symbols as typed. Blank means the default symbol (defined once, in `DiscreetSymbols`).
    @AppStorage("calendarSyncSymbolPeriod",  store: AppGroup.defaults) var calendarSyncSymbolPeriod: String = ""
    @AppStorage("calendarSyncSymbolFertile", store: AppGroup.defaults) var calendarSyncSymbolFertile: String = ""
    @AppStorage("calendarSyncSymbolPhase",   store: AppGroup.defaults) var calendarSyncSymbolPhase: String = ""

    // PDF export orientation, remembered separately for the calendar and the report. Plain
    // `PaperSize.Orientation` raw values, so this file still compiles in the widget target; the typed accessor
    // is in ExportView.swift.
    static let calendarPDFOrientationKey = "calendarPDFOrientation"
    static let reportPDFOrientationKey = "reportPDFOrientation"
    @AppStorage(AppSettings.calendarPDFOrientationKey) var calendarPDFOrientation: String = "landscape"
    @AppStorage(AppSettings.reportPDFOrientationKey)   var reportPDFOrientation: String = "portrait"

    // Flags
    @AppStorage("hasPromptedNotifications") var hasPromptedNotifications: Bool = false
    @AppStorage("sharerName") var sharerName: String = ""

    // Tracking mode. Shared with the widget so its content can follow the mode later.
    @AppStorage("trackingMode", store: AppGroup.defaults) var trackingModeRaw: String = TrackingMode.cycle.rawValue
    /// "last" keeps the mode the user left the app in; otherwise a `TrackingMode` raw value.
    @AppStorage("defaultModeOnLaunch", store: AppGroup.defaults) var defaultModeOnLaunch: String = "last"

    /// Selected moon theme (`AppTheme.all`). Shared with the widgets. A Plus theme stays stored while Plus is
    /// off; `DS.Theme.current` shows Blush until it is back.
    @AppStorage(DS.Theme.storageKey, store: AppGroup.defaults) var themeID: String = AppTheme.defaultID

    // Greeting on Today. Plain values in the shared store so the widget can read them. Style is a
    // `GreetingStyle` raw value ("greeting", "name" or "off"); the name is only used with "name".
    static let greetingStyleKey = "greetingStyle"
    static let greetingNameKey = "greetingName"
    @AppStorage(AppSettings.greetingStyleKey, store: AppGroup.defaults) var greetingStyleRaw: String = GreetingStyle.greeting.rawValue
    @AppStorage(AppSettings.greetingNameKey, store: AppGroup.defaults) var greetingName: String = ""

    var greetingStyle: GreetingStyle {
        get { GreetingStyle(stored: greetingStyleRaw) }
        set { greetingStyleRaw = newValue.rawValue }
    }

    var trackingMode: TrackingMode {
        get { TrackingMode(rawValue: trackingModeRaw) ?? .cycle }
        set { trackingModeRaw = newValue.rawValue }
    }

    /// Called at launch. A fixed default mode replaces the remembered one; "last" and unknown values change nothing.
    /// When the mode does change, the widgets reload so the Quick Log chips follow it.
    func applyLaunchMode() {
        guard defaultModeOnLaunch != "last", let fixed = TrackingMode(rawValue: defaultModeOnLaunch),
              fixed != trackingMode else { return }
        trackingMode = fixed
        AppGroup.reloadWidgets()
    }

    /// The fixed phase color (adaptive light and dark). Any custom color stored by 1.9.x is ignored.
    func phaseColor(for phase: Event.EventType) -> Color {
        phase.defaultPhaseColor
    }
}
