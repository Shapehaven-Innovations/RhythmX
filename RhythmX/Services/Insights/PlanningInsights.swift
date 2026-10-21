//  PlanningInsights.swift
//  Pure numbers behind the Planning mode of the Insights tab. No UI, no persistence.

import Foundation

struct PlanningInsights: Equatable {
    enum Level: Equatable { case low, rising, high, peak }

    struct TempPoint: Equatable, Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    enum TestResult: String, Equatable, CaseIterable {
        case negative = "Ovulation Test Negative"
        case faint    = "Ovulation Test Faint"
        case positive = "Ovulation Test Positive"
        case peak     = "Ovulation Test Peak"

        var title: String {
            switch self {
            case .negative: return "Negative"
            case .faint:    return "Faint"
            case .positive: return "Positive"
            case .peak:     return "Peak"
            }
        }
    }

    struct TestPoint: Equatable, Identifiable {
        let date: Date
        let result: TestResult
        var id: Date { date }
    }

    /// First to last fertile day, from `FertileWindow` (auto days plus the user's manual changes).
    let fertileWindow: ClosedRange<Date>?
    /// The first ovulation-phase day of the current cycle.
    let likelyOvulation: Date?
    /// Days from today to the likely ovulation day; nil without a cycle or once that day has passed.
    let daysToOvulation: Int?
    let fertilityLevel: Level
    /// Days past ovulation, 1 to 14; nil before ovulation and after the wait is over.
    /// Counts from the latest peak or positive test when there is one, else from the likely day.
    let twoWeekWaitDay: Int?
    /// "Basal Temp:<number>" tags on cycle events plus the Apple Health readings passed in that fall in
    /// the current cycle, one per day, oldest first. A logged tag wins over the Health value for the same day.
    let temperatures: [TempPoint]
    /// Ovulation test tags on cycle events, oldest first.
    let testResults: [TestPoint]

    var hasCycle: Bool { likelyOvulation != nil || fertileWindow != nil }
    var latestTest: TestPoint? { testResults.last }

    /// Days before the window opens during which fertility reads as rising.
    static let risingDays = 3
    static let twoWeekWaitLength = 14

    /// - Parameter importedTemperatures: readings from Apple Health (`HealthSync.importedTemperatures`). They
    ///   only feed the chart; nothing here writes them into events.
    static func make(events: [Event], overrides: FertileOverrides, today: Date,
                     importedTemperatures: [TempPoint] = [],
                     calendar: Calendar = .current) -> PlanningInsights {
        let today = calendar.startOfDay(for: today)
        let cycleEvents = events.filter { $0.effectiveMode != .menopause }

        let windowDays = FertileWindow.days(events: cycleEvents, overrides: overrides, calendar: calendar)
            .compactMap { date(fromDayKey: $0, calendar: calendar) }
        let window: ClosedRange<Date>? = {
            guard let first = windowDays.min(), let last = windowDays.max() else { return nil }
            return first...last
        }()

        // The current cycle is the one whose start (first day of a run of menstrual days) is the latest
        // on or before today; before any cycle has started, it is the earliest. Likely ovulation is the
        // first ovulation-phase day inside that cycle, never an older cycle's day.
        let menstrualDays = Set(cycleEvents.filter { $0.eventType == .menstrual }.map { calendar.startOfDay(for: $0.date) })
        let cycleStarts = menstrualDays.filter { day in
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return true }
            return !menstrualDays.contains(previous)
        }.sorted()
        let currentStart = cycleStarts.last { $0 <= today } ?? cycleStarts.first
        let nextStart = currentStart.flatMap { start in cycleStarts.first { $0 > start } }
        let ovulationDays = cycleEvents
            .filter { $0.eventType == .ovulation }
            .map { calendar.startOfDay(for: $0.date) }
        let inCurrentCycle = ovulationDays.filter { day in
            guard let currentStart else { return true }
            if day < currentStart { return false }
            if let nextStart, day >= nextStart { return false }
            return true
        }
        let likely = inCurrentCycle.min() ?? ovulationDays.min()

        let tests = cycleEvents
            .flatMap { event in
                TagParser.split(event.tags).compactMap { raw -> TestPoint? in
                    guard let result = TestResult(rawValue: TagParser.label(for: raw)) else { return nil }
                    return TestPoint(date: calendar.startOfDay(for: event.date), result: result)
                }
            }
            .sorted { $0.date < $1.date }

        let taggedTemperatures = cycleEvents
            .flatMap { event in
                TagParser.split(event.tags).compactMap { raw -> TempPoint? in
                    let parts = raw.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2,
                          parts[0].trimmingCharacters(in: .whitespaces) == TagCategory.basalTemp.rawValue,
                          let value = temperature(from: String(parts[1])) else { return nil }
                    return TempPoint(date: calendar.startOfDay(for: event.date), value: value)
                }
            }
        let taggedDays = Set(taggedTemperatures.map(\.date))
        // Health readings cover a year; only the current cycle's are shown, from its start up to the next
        // cycle's start, or through today when there is none. Without a cycle there is no range to show.
        let importedRange: (start: Date, end: Date)? = currentStart.map { start in
            (start, nextStart ?? calendar.date(byAdding: .day, value: 1, to: today) ?? today)
        }
        let temperatures = (taggedTemperatures + importedTemperatures
            .map { TempPoint(date: calendar.startOfDay(for: $0.date), value: $0.value) }
            .filter { point in
                guard let importedRange else { return false }
                return point.date >= importedRange.start && point.date < importedRange.end
            }
            .filter { !taggedDays.contains($0.date) })
            .sorted { $0.date < $1.date }

        func days(from a: Date, to b: Date) -> Int {
            calendar.dateComponents([.day], from: a, to: b).day ?? 0
        }

        var daysToOvulation: Int?
        if let likely {
            let d = days(from: today, to: likely)
            if d >= 0 { daysToOvulation = d }
        }

        // Ovulation is confirmed by the latest peak test, else the latest positive test, on or before today.
        let confirmed = tests.filter { $0.date <= today && $0.result == .peak }.last?.date
            ?? tests.filter { $0.date <= today && $0.result == .positive }.last?.date
        var twoWeekWaitDay: Int?
        if let anchor = confirmed ?? likely {
            let dpo = days(from: anchor, to: today)
            if (1...twoWeekWaitLength).contains(dpo) { twoWeekWaitDay = dpo }
        }

        let testToday = tests.last { $0.date == today }?.result
        let level: Level
        if likely == today || testToday == .peak || testToday == .positive {
            level = .peak
        } else if let window, window.contains(today) {
            level = .high
        } else if let window, today < window.lowerBound, days(from: today, to: window.lowerBound) <= risingDays {
            level = .rising
        } else {
            level = .low
        }

        return PlanningInsights(
            fertileWindow: window,
            likelyOvulation: likely,
            daysToOvulation: daysToOvulation,
            fertilityLevel: level,
            twoWeekWaitDay: twoWeekWaitDay,
            temperatures: temperatures,
            testResults: tests
        )
    }

    /// "97.8", " 97.4" and "36.6 C" all read as numbers; "Elevated BBT" does not.
    static func temperature(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed) { return value }
        let numeric = trimmed.prefix { $0.isNumber || $0 == "." }
        guard !numeric.isEmpty else { return nil }
        return Double(numeric)
    }

    /// Inverse of `FertileWindow.dayKey`.
    static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            .map { calendar.startOfDay(for: $0) }
    }
}
