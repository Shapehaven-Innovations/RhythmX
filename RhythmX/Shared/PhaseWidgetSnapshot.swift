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

    init(phase: Event.EventType?, cycleDay: Int?, daysUntilNext: Int?, overdueDays: Int? = nil,
         nextPhase: Event.EventType? = nil, daysUntilNextPhase: Int? = nil,
         cycleLength: Int? = nil, nextPeriodDate: Date? = nil,
         isFertileToday: Bool = false, fertileEndsIn: Int? = nil, fertileStartsIn: Int? = nil) {
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
    }

    var isActive: Bool { cycleDay != nil }

    /// Period starts within 3 days (and has not started): small widget highlights it.
    var isPeriodSoon: Bool { (daysUntilNext ?? Int.max) <= Self.periodSoonDays }

    static let periodSoonDays = 3

    static let sample = PhaseWidgetSnapshot(
        phase: .follicular, cycleDay: 8, daysUntilNext: 20,
        nextPhase: .ovulation, daysUntilNextPhase: 5, cycleLength: 28,
        nextPeriodDate: Calendar.current.date(byAdding: .day, value: 20, to: Date().startOfDay),
        isFertileToday: true, fertileEndsIn: 7)

    static func make(events: [Event], archived: [ArchivedDataBlock], today: Date,
                     fertileOverrides: FertileOverrides = FertileOverrides()) -> PhaseWidgetSnapshot {
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
                                   isFertileToday: fertileToday, fertileEndsIn: endsIn, fertileStartsIn: startsIn)
    }

    static func load(defaults: UserDefaults = AppGroup.defaults, today: Date = Date()) -> PhaseWidgetSnapshot {
        let events = defaults.data(forKey: PersistenceKeys.events)
            .flatMap { try? JSONDecoder().decode([Event].self, from: $0) } ?? []
        let archived = defaults.data(forKey: PersistenceKeys.archivedData)
            .flatMap { try? JSONDecoder().decode([ArchivedDataBlock].self, from: $0) } ?? []
        return make(events: events, archived: archived, today: today,
                    fertileOverrides: FertileWindow.loadOverrides(from: defaults))
    }

    /// One entry per day starting now, so the widget stays correct if the midnight reload is delayed.
    static func timeline(defaults: UserDefaults = AppGroup.defaults, from now: Date = Date(), days: Int = 7)
        -> [(date: Date, snapshot: PhaseWidgetSnapshot)] {
        let events = defaults.data(forKey: PersistenceKeys.events)
            .flatMap { try? JSONDecoder().decode([Event].self, from: $0) } ?? []
        let archived = defaults.data(forKey: PersistenceKeys.archivedData)
            .flatMap { try? JSONDecoder().decode([ArchivedDataBlock].self, from: $0) } ?? []
        let overrides = FertileWindow.loadOverrides(from: defaults)
        return (0..<max(days, 1)).map { offset in
            let date = offset == 0 ? now : now.startOfDay.diff(numDays: offset)
            return (date, make(events: events, archived: archived, today: date, fertileOverrides: overrides))
        }
    }
}
