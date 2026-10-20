//  MenopauseInsights.swift
//  Pure numbers behind the Menopause mode of the Insights tab. No cycle, no prediction, no UI.

import Foundation

struct MenopauseInsights: Equatable {
    struct WeekRow: Equatable, Identifiable {
        let label: String
        let count: Int
        var id: String { label }
    }

    /// The latest cycle period day on or before today. Logging a period resets the count.
    let lastPeriod: Date?
    /// Whole months from the last period to today; 0 without a period.
    let monthsSinceLastPeriod: Int
    /// Hot flash occurrences in each of the last 8 rolling weeks, oldest first. Each tag counts once.
    let hotFlashesPerWeek: [Int]
    /// Tag label to occurrence count for the current week (today and the 6 days before).
    let weekSummary: [String: Int]

    static let weeks = 8
    static let monthsGoal = 12
    static let hotFlashesLabel = "Hot Flashes"

    var hasData: Bool {
        lastPeriod != nil || hotFlashesPerWeek.contains { $0 > 0 } || !weekSummary.isEmpty
    }

    /// Week summary as rows, most frequent first, then alphabetical.
    var weekRows: [WeekRow] {
        weekSummary
            .map { WeekRow(label: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
    }

    var hotFlashesThisWeek: Int { hotFlashesPerWeek.last ?? 0 }

    static func make(events: [Event], today: Date, calendar: Calendar = .current) -> MenopauseInsights {
        let today = calendar.startOfDay(for: today)

        let lastPeriod = events
            .filter { $0.eventType == .menstrual && $0.effectiveMode == .cycle }
            .map { calendar.startOfDay(for: $0.date) }
            .filter { $0 <= today }
            .max()

        let months = lastPeriod.flatMap { calendar.dateComponents([.month], from: $0, to: today).month } ?? 0

        var perWeek = Array(repeating: 0, count: weeks)
        var summary: [String: Int] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            guard let daysAgo = calendar.dateComponents([.day], from: day, to: today).day, daysAgo >= 0 else { continue }
            let week = daysAgo / 7
            guard week < weeks else { continue }
            for raw in TagParser.split(event.tags) {
                let label = TagParser.label(for: raw)
                if label == hotFlashesLabel { perWeek[weeks - 1 - week] += 1 }
                if week == 0, isSurfaced(raw) { summary[label, default: 0] += 1 }
            }
        }

        return MenopauseInsights(
            lastPeriod: lastPeriod,
            monthsSinceLastPeriod: max(0, months),
            hotFlashesPerWeek: perWeek,
            weekSummary: summary
        )
    }

    /// Menopause and Mood tags, plus the Menopause library's labels logged under another category
    /// (for example the older "Other:Hot Flashes" and "Other:Poor Sleep").
    private static func isSurfaced(_ raw: String) -> Bool {
        let parts = raw.split(separator: ":", maxSplits: 1)
        let category = parts.count == 2 ? parts[0].trimmingCharacters(in: .whitespaces) : ""
        if category == TagCategory.menopause.rawValue || category == TagCategory.mood.rawValue { return true }
        return (TagLibrary.tags[.menopause] ?? []).contains(TagParser.label(for: raw))
    }
}
