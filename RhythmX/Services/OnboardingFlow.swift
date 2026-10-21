//  OnboardingFlow.swift
//  Pure rules behind the onboarding pages: the five pages and their buttons, the optional last period start
//  (logged through the same plan Log Period on Today uses, and only on a phone with no cycle data yet, so a
//  replay or a restore is never overwritten), and the permissions primer, where nothing asks iOS for anything
//  until the person taps.

import Foundation

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome, mode, lastPeriod, phases, makeItYours

    var id: Int { rawValue }
    var index: Int { rawValue }
    static var count: Int { allCases.count }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }

    /// Skip ends the flow from any page; the last page's own button does the same.
    var showsSkip: Bool { self != .makeItYours }
    var showsBack: Bool { self != .welcome }

    var primaryTitle: String { primaryTitle(replay: false) }

    func primaryTitle(replay: Bool) -> String {
        guard self == .makeItYours else { return "Continue" }
        return replay ? "Done" : "Start Tracking"
    }

    var accessibilityPosition: String { "Page \(index + 1) of \(Self.count)" }

    /// The pages shown for a mode. Menopause has no periods to log, so the last period page is left out.
    static func pages(for mode: TrackingMode) -> [OnboardingPage] {
        mode == .menopause ? allCases.filter { $0 != .lastPeriod } : allCases
    }

    func next(for mode: TrackingMode) -> OnboardingPage? {
        let pages = Self.pages(for: mode)
        guard let i = pages.firstIndex(of: self) else { return next }
        return i + 1 < pages.count ? pages[i + 1] : nil
    }

    func previous(for mode: TrackingMode) -> OnboardingPage? {
        let pages = Self.pages(for: mode)
        guard let i = pages.firstIndex(of: self) else { return previous }
        return i > 0 ? pages[i - 1] : nil
    }

    func accessibilityPosition(for mode: TrackingMode) -> String {
        let pages = Self.pages(for: mode)
        let i = pages.firstIndex(of: self) ?? index
        return "Page \(i + 1) of \(pages.count)"
    }

    var title: String {
        switch self {
        case .welcome:     return "Know your rhythm."
        case .mode:        return "What are you tracking?"
        case .lastPeriod:  return "When did your last period start?"
        case .phases:      return "Four phases, four powers"
        case .makeItYours: return "Make it yours"
        }
    }

    var body: String? {
        switch self {
        case .welcome:     return "Track your cycle, notice your patterns, and keep it all to yourself. No account, no cloud."
        case .mode:        return "You can switch any time at the top of Today."
        case .lastPeriod:  return "Optional. Predictions get better with each period you log."
        case .phases:      return "Log how a day feels from Today in two taps: the plus, then a tag."
        case .makeItYours: return "Nothing turns on until you tap. Back up to Files any time from Settings."
        }
    }
}

/// The optional "When did your last period start?" answer.
enum OnboardingPeriodStart {
    static let cycleLength = 28
    /// How far back the date picker goes.
    static let daysBack = 90

    static func hasCycleData(_ events: [Event]) -> Bool {
        events.contains { $0.effectiveMode != .menopause }
    }

    static func pickerRange(today: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        let end = calendar.startOfDay(for: today)
        let start = calendar.date(byAdding: .day, value: -daysBack, to: end) ?? end
        return start...end
    }

    /// The Log Period plan (`PeriodStartPlan`) for a cycle starting on `start`; nil when nothing should change:
    /// no date was chosen, the date is in the future, or the phone already has cycle data.
    static func plan(events: [Event], start: Date?, today: Date, calendar: Calendar = .current) -> PeriodStartPlan.Result? {
        guard let start, !hasCycleData(events),
              calendar.startOfDay(for: start) <= calendar.startOfDay(for: today) else { return nil }
        return PeriodStartPlan.make(events: events, start: start, cycleLength: cycleLength, calendar: calendar)
    }

    /// What Continue on the last period page does. A period is logged only when the person actively chose a
    /// date (the picker showing today by default is not a choice), and never in Menopause mode.
    static func continuePlan(events: [Event], start: Date, chosen: Bool, mode: TrackingMode, today: Date,
                             calendar: Calendar = .current) -> PeriodStartPlan.Result? {
        guard chosen, mode != .menopause else { return nil }
        return plan(events: events, start: start, today: today, calendar: calendar)
    }
}

/// The last page's primer: Daily insights, Apple Health and Apple Calendar, each with one plain reason and
/// Enable or Later.
struct OnboardingPrimer: Equatable {
    enum Item: String, CaseIterable, Identifiable {
        case dailyInsights, appleHealth, appleCalendar
        var id: String { rawValue }

        var title: String {
            switch self {
            case .dailyInsights: return "Daily insights"
            case .appleHealth:   return "Apple Health"
            case .appleCalendar: return "Apple Calendar"
            }
        }

        var reason: String {
            switch self {
            case .dailyInsights: return "A short note and a reminder to log, once a day"
            case .appleHealth:   return "Period days to Health, temperature and sleep back"
            case .appleCalendar: return "Your phases in a calendar on this iPhone"
            }
        }

        var enableTitle: String {
            switch self {
            case .dailyInsights: return "Turn On"
            case .appleHealth:   return "Connect"
            case .appleCalendar: return "Add"
            }
        }

        var symbol: String {
            switch self {
            case .dailyInsights: return "moon.fill"
            case .appleHealth:   return "heart.fill"
            case .appleCalendar: return "calendar"
            }
        }

        /// What tapping Enable does. Daily insights first shows the Lock Screen preview and the privacy choice;
        /// only confirming that asks iOS (for notifications), so nothing is scheduled before the choice. Apple
        /// Health asks per switch, so it points to Settings; Calendar sync needs Plus.
        func enableAction(isPlus: Bool) -> EnableAction {
            switch self {
            case .dailyInsights: return .chooseLockScreenPrivacy
            case .appleHealth:   return .showInSettings
            case .appleCalendar: return isPlus ? .showInSettings : .explainPlus
            }
        }

        func detail(for state: State) -> String? {
            switch (self, state) {
            case (_, .idle): return nil
            case (.dailyInsights, .choosingPrivacy): return "Choose what your Lock Screen shows, then turn it on."
            case (.dailyInsights, .on): return "On. You can change the time in Settings."
            case (_, .on): return "On. You can change it in Settings."
            case (.dailyInsights, .denied): return "Notifications are off for RhythmX. You can allow them in iPhone Settings."
            case (.appleHealth, .inSettings): return "Settings opens when you finish. Turn on only what you want; Health asks then."
            case (.appleCalendar, .inSettings): return "Settings opens when you finish. Calendar asks when you turn sync on."
            case (.appleCalendar, .plusNeeded): return "Calendar sync is part of RhythmX Plus. You can see it in Settings."
            case (_, .later): return "Any time in Settings."
            default: return nil
            }
        }
    }

    enum EnableAction: Equatable {
        case chooseLockScreenPrivacy, requestNotifications, showInSettings, explainPlus
    }

    /// What confirming the Lock Screen choice does: only then is iOS asked and anything scheduled.
    static let confirmAction: EnableAction = .requestNotifications

    enum State: Equatable {
        case idle, choosingPrivacy, on, denied, inSettings, plusNeeded, later
    }

    /// The Lock Screen choice shown before Daily insights turns on. Private unless the person picks otherwise;
    /// it sets Lock Screen privacy (`AppSettings.dailyInsightsDiscreet`), which covers every notification.
    enum LockScreenChoice: String, CaseIterable, Identifiable {
        case showDetails, keepPrivate
        var id: String { rawValue }

        var title: String {
            switch self {
            case .showDetails: return "Show details on the Lock Screen"
            case .keepPrivate: return "Keep it private"
            }
        }

        var discreet: Bool { self == .keepPrivate }
    }

    var lockScreenChoice: LockScreenChoice = .keepPrivate

    /// The note as the Lock Screen would show it with `choice`.
    static func preview(_ insights: DailyInsights, choice: LockScreenChoice) -> NotificationsPage.Preview {
        NotificationsPage.insightPreview(insights, discreet: choice.discreet)
    }

    private var states: [Item: State] = [:]

    func state(_ item: Item) -> State { states[item] ?? .idle }
    mutating func set(_ item: Item, _ state: State) { states[item] = state }

    /// True when the person asked to set Health or Calendar up: the app opens on Settings.
    var opensSettingsOnFinish: Bool { states.values.contains(.inSettings) }
}
