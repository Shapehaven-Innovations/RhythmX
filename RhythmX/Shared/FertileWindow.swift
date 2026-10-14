//  FertileWindow.swift
//  Compiled into the app and the widget extension. Pure logic plus shared-defaults persistence.

import Foundation

/// Manual changes to the auto-derived window, keyed by "yyyy-MM-dd" so they survive time-zone changes.
struct FertileOverrides: Codable, Equatable {
    var added: Set<String> = []
    var removed: Set<String> = []
}

enum FertileWindow {
    static let overridesKey = "com.example.rhythm(x).fertileOverrides"
    /// Matches the Phases guide: up to five days before ovulation through the end of the ovulation phase.
    static let daysBeforeOvulation = 5

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Auto window from the logged Ovulation-phase days; empty when none are logged.
    static func autoDays(events: [Event], calendar: Calendar = .current) -> Set<String> {
        let dates = events.filter { $0.eventType == .ovulation }.map { calendar.startOfDay(for: $0.date) }
        guard let first = dates.min(), let last = dates.max(),
              let start = calendar.date(byAdding: .day, value: -daysBeforeOvulation, to: first) else { return [] }
        var result = Set<String>()
        var d = start
        while d <= last {
            result.insert(dayKey(d, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return result
    }

    /// (auto + added) - removed
    static func days(events: [Event], overrides: FertileOverrides, calendar: Calendar = .current) -> Set<String> {
        autoDays(events: events, calendar: calendar).union(overrides.added).subtracting(overrides.removed)
    }

    /// Flips one day, keeping overrides minimal (a day equal to the auto result leaves no override).
    static func toggled(_ overrides: FertileOverrides, date: Date, autoDays: Set<String>,
                        calendar: Calendar = .current) -> FertileOverrides {
        let k = dayKey(date, calendar: calendar)
        var o = overrides
        let fertile = (autoDays.contains(k) || o.added.contains(k)) && !o.removed.contains(k)
        if fertile {
            o.added.remove(k)
            if autoDays.contains(k) { o.removed.insert(k) }
        } else {
            o.removed.remove(k)
            if !autoDays.contains(k) { o.added.insert(k) }
        }
        return o
    }

    static func loadOverrides(from defaults: UserDefaults = AppGroup.defaults) -> FertileOverrides {
        defaults.data(forKey: overridesKey)
            .flatMap { try? JSONDecoder().decode(FertileOverrides.self, from: $0) } ?? FertileOverrides()
    }

    static func saveOverrides(_ overrides: FertileOverrides, to defaults: UserDefaults = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: overridesKey)
        AppGroup.reloadWidgets()
    }
}
