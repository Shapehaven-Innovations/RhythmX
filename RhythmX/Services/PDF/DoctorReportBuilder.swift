//  DoctorReportBuilder.swift
//
//  The numbers behind the Doctor Report. Cycle and Planning read cycle data only (legacy, Cycle and Planning
//  events and blocks; menopause entries never reach a cycle statistic). Menopause mode adds the variant built
//  from `MenopauseInsights`. The builder has no UI and stores nothing.

import Foundation

struct SymptomCount: Equatable, Identifiable {
    let label: String
    let count: Int
    var id: String { label }
}

/// Weekly menopause counts for the report's Menopause variant. Oldest week first, `MenopauseInsights.weeks` entries.
struct MenopauseReport: Equatable {
    let lastPeriod: Date?
    let monthsSinceLastPeriod: Int
    let hotFlashesPerWeek: [Int]
    let nightSweatsPerWeek: [Int]
    let poorSleepPerWeek: [Int]

    static let nightSweatsLabel = "Night Sweats"
    static let poorSleepLabel = "Poor Sleep"

    var hasData: Bool {
        lastPeriod != nil || (hotFlashesPerWeek + nightSweatsPerWeek + poorSleepPerWeek).contains { $0 > 0 }
    }
}

struct DoctorReport: Equatable {
    /// A cycle longer than this is marked long.
    static let longCycleDays = 45
    /// Bars on the chart.
    static let chartCycles = 6
    /// Completed cycles the report needs before it shows statistics.
    static let minimumCycles = 2

    /// A menstrual day this many days or fewer after its run's start is part of the same period.
    static let sameRunDays = 7

    /// Lengths of the last `chartCycles` completed cycles, oldest first. A cycle's length is the days from its
    /// period start to the next period start; the running cycle has none.
    let cycleLengths: [Int]
    /// Period start of each cycle in `cycleLengths`, same order.
    let cycleStarts: [Date]
    /// Mean of every completed cycle, not only the charted ones.
    let averageCycle: Double?
    let averagePeriod: Double?
    /// Population standard deviation of the completed cycle lengths; nil below two cycles.
    let variation: Double?
    /// Every period start, oldest first, including the running cycle's.
    let periodStarts: [Date]
    /// Up to six most logged Symptom tags, most frequent first.
    let topSymptoms: [SymptomCount]
    /// At least `minimumCycles` completed cycles.
    let hasEnoughData: Bool
    /// Indexes into `cycleLengths` whose length is over `longCycleDays`.
    let longCycleIndexes: Set<Int>
    /// The Menopause variant; only built in Menopause mode.
    let menopause: MenopauseReport?
}

enum DoctorReportBuilder {
    static func make(events: [Event], archivedBlocks: [ArchivedDataBlock], mode: TrackingMode,
                     today: Date, calendar: Calendar = .current) -> DoctorReport {
        let cycleEvents = events.filter { $0.effectiveMode != .menopause }
        let settings = AppSettings()

        let cycleBlocks = archivedBlocks.filter { $0.effectiveMode != .menopause }
        let blockEvents = cycleBlocks.map { block in block.groupedEvents.flatMap { $0.events } }

        // Period starts: the first day of each run of menstrual days across the archive and the live events,
        // oldest first. A menstrual day continues the run when it follows the previous menstrual day, or comes
        // within `sameRunDays` of the run's start (a spotting break, or a period split across two blocks).
        // Blocks with no menstrual day add no start.
        let menstrualDays = Set((blockEvents.flatMap { $0 } + cycleEvents)
            .filter { $0.eventType == .menstrual }
            .map { calendar.startOfDay(for: $0.date) })
        func days(_ from: Date, _ to: Date) -> Int { calendar.dateComponents([.day], from: from, to: to).day ?? 0 }
        var periodStarts: [Date] = []
        var lastMenstrual: Date?
        for day in menstrualDays.sorted() {
            defer { lastMenstrual = day }
            if let start = periodStarts.last, let last = lastMenstrual,
               days(last, day) <= 1 || days(start, day) <= DoctorReport.sameRunDays { continue }
            periodStarts.append(day)
        }

        // Completed cycles run from one period start to the next; the last start opens the running cycle,
        // which has no length yet.
        struct Completed {
            let start: Date
            let length: Int
        }
        let completed: [Completed] = zip(periodStarts, periodStarts.dropFirst()).compactMap { start, next in
            let length = days(start, next)
            return length > 0 ? Completed(start: start, length: length) : nil
        }

        let lengths = completed.map(\.length)
        let charted = Array(completed.suffix(DoctorReport.chartCycles))
        let averageCycle = lengths.isEmpty ? nil : Double(lengths.reduce(0, +)) / Double(lengths.count)
        let variation: Double? = {
            guard let mean = averageCycle, lengths.count >= 2 else { return nil }
            let squares = lengths.reduce(0.0) { $0 + pow(Double($1) - mean, 2) }
            return (squares / Double(lengths.count)).squareRoot()
        }()

        // Period length per archived block, the same calculation Insights shows (`cycleStats` over one block).
        let archivedPeriods = cycleBlocks.compactMap { block in
            InsightsViewModel(events: [], archivedBlocks: [block], appSettings: settings).cycleStats(today: today).averagePeriodLength
        }
        let currentPeriod = cycleEvents.filter { $0.eventType == .menstrual }.count
        let periods = archivedPeriods.isEmpty ? (currentPeriod > 0 ? [currentPeriod] : []) : archivedPeriods
        let averagePeriod = periods.isEmpty ? nil : Double(periods.reduce(0, +)) / Double(periods.count)

        let symptoms = topSymptoms(in: blockEvents.flatMap { $0 } + cycleEvents)

        return DoctorReport(
            cycleLengths: charted.map(\.length),
            cycleStarts: charted.map(\.start),
            averageCycle: averageCycle,
            averagePeriod: averagePeriod,
            variation: variation,
            periodStarts: periodStarts,
            topSymptoms: symptoms,
            hasEnoughData: completed.count >= DoctorReport.minimumCycles,
            longCycleIndexes: Set(charted.enumerated().filter { $0.element.length > DoctorReport.longCycleDays }.map(\.offset)),
            menopause: mode == .menopause ? makeMenopause(events: events, today: today, calendar: calendar) : nil
        )
    }

    /// Symptom-category tags only, each occurrence counted, most frequent first, then by label.
    static func topSymptoms(in events: [Event], limit: Int = 6) -> [SymptomCount] {
        var counts: [String: Int] = [:]
        for event in events {
            for raw in TagParser.split(event.tags) {
                let parts = raw.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespaces) == TagCategory.symptom.rawValue else { continue }
                let label = TagParser.label(for: raw)
                guard !label.isEmpty else { continue }
                counts[label, default: 0] += 1
            }
        }
        return counts
            .map { SymptomCount(label: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
            .prefix(limit)
            .map { $0 }
    }

    /// The Menopause variant. Months since the last period and the hot flash weeks come from `MenopauseInsights`;
    /// night sweats and poor sleep use the same rolling weeks.
    static func makeMenopause(events: [Event], today: Date, calendar: Calendar = .current) -> MenopauseReport {
        let insights = MenopauseInsights.make(events: events, today: today, calendar: calendar)
        return MenopauseReport(
            lastPeriod: insights.lastPeriod,
            monthsSinceLastPeriod: insights.monthsSinceLastPeriod,
            hotFlashesPerWeek: insights.hotFlashesPerWeek,
            nightSweatsPerWeek: weeklyCounts(of: MenopauseReport.nightSweatsLabel, in: events, today: today, calendar: calendar),
            poorSleepPerWeek: weeklyCounts(of: MenopauseReport.poorSleepLabel, in: events, today: today, calendar: calendar)
        )
    }

    /// Occurrences of a tag label (any category) in each of the last `MenopauseInsights.weeks` rolling weeks, oldest first.
    static func weeklyCounts(of label: String, in events: [Event], today: Date, calendar: Calendar) -> [Int] {
        let weeks = MenopauseInsights.weeks
        let todayStart = calendar.startOfDay(for: today)
        var perWeek = Array(repeating: 0, count: weeks)
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            guard let daysAgo = calendar.dateComponents([.day], from: day, to: todayStart).day, daysAgo >= 0 else { continue }
            let week = daysAgo / 7
            guard week < weeks else { continue }
            for raw in TagParser.split(event.tags) where TagParser.label(for: raw) == label {
                perWeek[weeks - 1 - week] += 1
            }
        }
        return perWeek
    }
}
