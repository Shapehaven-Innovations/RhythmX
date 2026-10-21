//  PhaseWidgetSnapshot.swift
//  Compiled into the app, the widget extension, and (via @testable) the tests.

import Foundation

struct PhaseWidgetSnapshot: Equatable {
    let phase: Event.EventType?
    let cycleDay: Int?
    let daysUntilNext: Int?     // nil when unknown or already overdue
    let overdueDays: Int?       // days past the expected start; nil when not overdue
    let nextPhase: Event.EventType?     // nil unless a cycle day and current phase are known
    let daysUntilNextPhase: Int?
    let cycleLength: Int?               // length of the current cycle in days
    let nextPeriodDate: Date?           // nil when overdue or unknown
    let isFertileToday: Bool
    let fertileEndsIn: Int?             // days until the last day of today's window (0 = ends today)
    let fertileStartsIn: Int?           // days until the next window starts; nil if in one or none upcoming
    let cycleStartDate: Date?           // first logged day of the current cycle; nil when no cycle day applies
    let averageCycleLength: Int?
    let averagePeriodLength: Int?

    init(phase: Event.EventType?, cycleDay: Int?, daysUntilNext: Int?, overdueDays: Int? = nil,
         nextPhase: Event.EventType? = nil, daysUntilNextPhase: Int? = nil,
         cycleLength: Int? = nil, nextPeriodDate: Date? = nil,
         isFertileToday: Bool = false, fertileEndsIn: Int? = nil, fertileStartsIn: Int? = nil,
         cycleStartDate: Date? = nil, averageCycleLength: Int? = nil, averagePeriodLength: Int? = nil) {
        self.phase = phase
        self.cycleDay = cycleDay
        self.daysUntilNext = daysUntilNext
        self.overdueDays = overdueDays
        self.nextPhase = nextPhase
        self.daysUntilNextPhase = daysUntilNextPhase
        self.cycleLength = cycleLength
        self.nextPeriodDate = nextPeriodDate
        self.isFertileToday = isFertileToday
        self.fertileEndsIn = fertileEndsIn
        self.fertileStartsIn = fertileStartsIn
        self.cycleStartDate = cycleStartDate
        self.averageCycleLength = averageCycleLength
        self.averagePeriodLength = averagePeriodLength
    }

    var isActive: Bool { cycleDay != nil }

    /// Period starts within 3 days (and has not started): small widget highlights it.
    var isPeriodSoon: Bool { (daysUntilNext ?? Int.max) <= Self.periodSoonDays }

    static let periodSoonDays = 3

    static let sample = PhaseWidgetSnapshot(
        phase: .follicular, cycleDay: 8, daysUntilNext: 20,
        nextPhase: .ovulation, daysUntilNextPhase: 5, cycleLength: 28,
        nextPeriodDate: Calendar.current.date(byAdding: .day, value: 20, to: Date().startOfDay),
        isFertileToday: true, fertileEndsIn: 7,
        cycleStartDate: Calendar.current.date(byAdding: .day, value: -7, to: Date().startOfDay),
        averageCycleLength: 28, averagePeriodLength: 5)

    static func make(events: [Event], archived: [ArchivedDataBlock], today: Date,
                     fertileOverrides: FertileOverrides = FertileOverrides()) -> PhaseWidgetSnapshot {
        // The widget reads the raw shared store, so the mode filter lives here: menopause data never
        // shapes the cycle day, the next period estimate or the fertile window.
        let events = events.filter { $0.effectiveMode != .menopause }
        let archived = archived.filter { $0.effectiveMode != .menopause }
        let stats = InsightsViewModel(events: events, archivedBlocks: archived, appSettings: AppSettings())
            .cycleStats(today: today)
        var until: Int?
        var overdue: Int?
        if let next = stats.nextPeriodEstimate,
           let d = Calendar.current.dateComponents([.day], from: today.startOfDay, to: next.startOfDay).day {
            if d >= 0 { until = d } else { overdue = -d }
        }

        var nextPhase: Event.EventType?
        var untilPhase: Int?
        if let phase = stats.currentPhase, stats.currentCycleDay != nil {
            let upcoming = events
                .filter { $0.date.startOfDay > today.startOfDay && $0.eventType != phase }
                .min { $0.date < $1.date }
            if let upcoming {
                nextPhase = upcoming.eventType
                untilPhase = Calendar.current.dateComponents([.day], from: today.startOfDay, to: upcoming.date.startOfDay).day
            } else if phase == .luteal, let until {
                nextPhase = .menstrual
                untilPhase = until
            }
        }

        var length: Int?
        if let day = stats.currentCycleDay, let until { length = until + day - 1 }

        let fertile = FertileWindow.days(events: events, overrides: fertileOverrides)
        let cal = Calendar.current
        func key(_ offset: Int) -> String {
            FertileWindow.dayKey(cal.date(byAdding: .day, value: offset, to: today.startOfDay) ?? today)
        }
        let fertileToday = fertile.contains(key(0))
        var endsIn: Int?
        var startsIn: Int?
        if fertileToday {
            var off = 0
            while fertile.contains(key(off + 1)) { off += 1 }
            endsIn = off
        } else {
            startsIn = (1...60).first { fertile.contains(key($0)) }
        }

        return PhaseWidgetSnapshot(phase: stats.currentPhase, cycleDay: stats.currentCycleDay,
                                   daysUntilNext: until, overdueDays: overdue,
                                   nextPhase: nextPhase, daysUntilNextPhase: untilPhase,
                                   cycleLength: length, nextPeriodDate: until == nil ? nil : stats.nextPeriodEstimate,
                                   isFertileToday: fertileToday, fertileEndsIn: endsIn, fertileStartsIn: startsIn,
                                   cycleStartDate: stats.currentCycleDay == nil ? nil : events.map(\.date).min()?.startOfDay,
                                   averageCycleLength: stats.averageCycleLength,
                                   averagePeriodLength: stats.averagePeriodLength)
    }

    static func load(defaults: UserDefaults = AppGroup.defaults, today: Date = Date()) -> PhaseWidgetSnapshot {
        let events = loadEvents(from: defaults)
        let archived = defaults.data(forKey: PersistenceKeys.archivedData)
            .flatMap { try? JSONDecoder().decode([ArchivedDataBlock].self, from: $0) } ?? []
        return make(events: events, archived: archived, today: today,
                    fertileOverrides: FertileWindow.loadOverrides(from: defaults))
    }

    /// One entry per day starting now, so the widget stays correct if the midnight reload is delayed.
    static func timeline(defaults: UserDefaults = AppGroup.defaults, from now: Date = Date(), days: Int = 7)
        -> [(date: Date, snapshot: PhaseWidgetSnapshot)] {
        let events = loadEvents(from: defaults)
        let archived = defaults.data(forKey: PersistenceKeys.archivedData)
            .flatMap { try? JSONDecoder().decode([ArchivedDataBlock].self, from: $0) } ?? []
        let overrides = FertileWindow.loadOverrides(from: defaults)
        return (0..<max(days, 1)).map { offset in
            let date = offset == 0 ? now : now.startOfDay.diff(numDays: offset)
            return (date, make(events: events, archived: archived, today: date, fertileOverrides: overrides))
        }
    }

    static func loadEvents(from defaults: UserDefaults = AppGroup.defaults) -> [Event] {
        defaults.data(forKey: PersistenceKeys.events)
            .flatMap { try? JSONDecoder().decode([Event].self, from: $0) } ?? []
    }

    // MARK: - Week Strip

    /// The seven days of the week that contains `today` (per the current calendar's first weekday), each with
    /// that day's phase. Only cycle events count: a menopause carrier never shows as a phase (Review Focus 2).
    static func weekDays(events: [Event], today: Date) -> [WeekStripDay] {
        let cal = Calendar.current
        let todayStart = today.startOfDay
        let start = cal.dateInterval(of: .weekOfYear, for: todayStart)?.start ?? todayStart
        var phaseByDay: [Date: Event.EventType] = [:]
        for event in events where event.effectiveMode != .menopause {
            let day = event.date.startOfDay
            if phaseByDay[day] == nil { phaseByDay[day] = event.eventType }
        }
        return (0..<7).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: start) ?? start
            return WeekStripDay(date: date, phase: phaseByDay[date], isToday: date == todayStart)
        }
    }
}

struct WeekStripDay: Equatable {
    let date: Date
    let phase: Event.EventType?
    let isToday: Bool
}

// MARK: - Plus widgets

/// The Plus gate the Week Strip and Quick Log widgets share. The widget extension cannot ask the store, so it
/// reads the cached expiry and keeps Plus for `Entitlement.plusGrace` after it (Review Focus 5); after that
/// it shows the upgrade prompt, whose tap opens the paywall in the app.
enum PlusWidgetState: Equatable {
    case locked
    case unlocked

    static let paywallURL = URL(string: "rhythmx://paywall")!

    static func make(entitlement: Entitlement, now: Date) -> PlusWidgetState {
        entitlement.isPlus(now: now) ? .unlocked : .locked
    }

    /// The instant an unlocked widget becomes locked (expiry plus grace), so a timeline can flip exactly then.
    static func lockDate(entitlement: Entitlement) -> Date? {
        entitlement.plusExpiry?.addingTimeInterval(Entitlement.plusGrace)
    }

    /// One timeline entry: its date and the Plus state at that date.
    struct Slot: Equatable {
        let date: Date
        let state: PlusWidgetState
    }

    /// The entries a Plus widget provider builds (pure, so it is tested without WidgetKit): one slot per date in
    /// `base`, plus one at the lock instant when it falls after `now` and before `horizon` and is not already
    /// there, so the widget flips to the upgrade prompt exactly at expiry plus grace without waiting for a
    /// reload (Review Focus 5). Sorted by date; each slot carries the state for its own date.
    static func timeline(base: [Date], now: Date, horizon: Date, entitlement: Entitlement) -> [Slot] {
        var dates = base
        if let lock = lockDate(entitlement: entitlement), lock > now, lock < horizon, !dates.contains(lock) {
            dates.append(lock)
        }
        return dates.sorted().map { Slot(date: $0, state: make(entitlement: entitlement, now: $0)) }
    }

    static func isPaywallLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "rhythmx" && url.host?.lowercased() == "paywall"
    }

    /// Deep-link copy shown while locked.
    static let lockedTitle = "RhythmX Plus"
    static let lockedSubtitle = "Tap to unlock"
}

typealias WeekStripWidgetState = PlusWidgetState
