//  AppSettings.swift

import SwiftUI

final class AppSettings: ObservableObject {
    // Phase colors (hex strings, default to DS token values)
    @AppStorage("phaseColor1", store: AppGroup.defaults) var phaseColor1: String = "#C97C7C"
    @AppStorage("phaseColor2", store: AppGroup.defaults) var phaseColor2: String = "#7CA68C"
    @AppStorage("phaseColor3", store: AppGroup.defaults) var phaseColor3: String = "#C9A87C"
    @AppStorage("phaseColor4", store: AppGroup.defaults) var phaseColor4: String = "#8C7CA6"

    // Notifications
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false
    @AppStorage("notifyDayBefore")      var notifyDayBefore: Bool = true
    @AppStorage("notifyDayOf")          var notifyDayOf: Bool = true

    // Fertile window reminders (Cycle and Planning only; never scheduled in Menopause). Off by default.
    @AppStorage("fertileStartOn")     var fertileStartOn: Bool = false
    @AppStorage("fertileOvulationOn") var fertileOvulationOn: Bool = false

    // Check-ins, kept as JSON (`CheckInSetting`) so this file still compiles in the widget target,
    // which has no reminder types. The typed accessors are in LoggingReminder.swift.
    @AppStorage("dailyCheckIn")  var dailyCheckInData: Data?
    @AppStorage("weeklyCheckIn") var weeklyCheckInData: Data?

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

    /// Changes whenever any phase color changes; lets views trigger a widget reload.
    var colorSignature: String { phaseColor1 + phaseColor2 + phaseColor3 + phaseColor4 }

    func phaseColor(for phase: Event.EventType) -> Color {
        let hex: String
        switch phase {
        case .menstrual:  hex = phaseColor1
        case .follicular: hex = phaseColor2
        case .ovulation:  hex = phaseColor3
        case .luteal:     hex = phaseColor4
        }
        return Color(hex: hex) ?? phase.defaultPhaseColor
    }

    func resetToDefaults() {
        phaseColor1 = "#C97C7C"
        phaseColor2 = "#7CA68C"
        phaseColor3 = "#C9A87C"
        phaseColor4 = "#8C7CA6"
    }
}
