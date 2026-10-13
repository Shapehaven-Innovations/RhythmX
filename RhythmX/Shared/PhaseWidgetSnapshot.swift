//  PhaseWidgetSnapshot.swift
//  Compiled into the app, the widget extension, and (via @testable) the tests.

import Foundation

struct PhaseWidgetSnapshot: Equatable {
    let phase: Event.EventType?
    let cycleDay: Int?
    let daysUntilNext: Int?     // nil when unknown or already overdue
    let overdueDays: Int?       // days past the expected start; nil when not overdue

    init(phase: Event.EventType?, cycleDay: Int?, daysUntilNext: Int?, overdueDays: Int? = nil) {
        self.phase = phase
        self.cycleDay = cycleDay
        self.daysUntilNext = daysUntilNext
        self.overdueDays = overdueDays
    }

    var isActive: Bool { cycleDay != nil }

    static let sample = PhaseWidgetSnapshot(phase: .follicular, cycleDay: 8, daysUntilNext: 20)

    static func make(events: [Event], archived: [ArchivedDataBlock], today: Date) -> PhaseWidgetSnapshot {
        let stats = InsightsViewModel(events: events, archivedBlocks: archived, appSettings: AppSettings())
            .cycleStats(today: today)
        var until: Int?
        var overdue: Int?
        if let next = stats.nextPeriodEstimate,
           let d = Calendar.current.dateComponents([.day], from: today.startOfDay, to: next.startOfDay).day {
            if d >= 0 { until = d } else { overdue = -d }
        }
        return PhaseWidgetSnapshot(phase: stats.currentPhase, cycleDay: stats.currentCycleDay,
                                   daysUntilNext: until, overdueDays: overdue)
    }

    static func load(defaults: UserDefaults = AppGroup.defaults, today: Date = Date()) -> PhaseWidgetSnapshot {
        let events = defaults.data(forKey: PersistenceKeys.events)
            .flatMap { try? JSONDecoder().decode([Event].self, from: $0) } ?? []
        let archived = defaults.data(forKey: PersistenceKeys.archivedData)
            .flatMap { try? JSONDecoder().decode([ArchivedDataBlock].self, from: $0) } ?? []
        return make(events: events, archived: archived, today: today)
    }

    /// One entry per day starting now, so the widget stays correct if the midnight reload is delayed.
    static func timeline(defaults: UserDefaults = AppGroup.defaults, from now: Date = Date(), days: Int = 7)
        -> [(date: Date, snapshot: PhaseWidgetSnapshot)] {
        let events = defaults.data(forKey: PersistenceKeys.events)
            .flatMap { try? JSONDecoder().decode([Event].self, from: $0) } ?? []
        let archived = defaults.data(forKey: PersistenceKeys.archivedData)
            .flatMap { try? JSONDecoder().decode([ArchivedDataBlock].self, from: $0) } ?? []
        return (0..<max(days, 1)).map { offset in
            let date = offset == 0 ? now : now.startOfDay.diff(numDays: offset)
            return (date, make(events: events, archived: archived, today: date))
        }
    }
}
