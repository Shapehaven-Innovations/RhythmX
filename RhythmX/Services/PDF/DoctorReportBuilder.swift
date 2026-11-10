//  DoctorReportBuilder.swift
//
//  The numbers behind the Doctor Report. Cycle and Planning read cycle data only (legacy, Cycle and Planning
//  events and blocks; menopause entries never reach a cycle statistic). Menopause mode adds the variant built
//  from `MenopauseInsights`. Skin and sexual activity are optional sections the person switches on or off in the
//  report options; they read the same events as the rest of the report (cycle data, or everything in Menopause
//  mode) and take a day's phase from `SkinStats`, so menopause entries never supply one. The builder has no UI
//  and stores nothing.

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

/// The Skin section: per area, logged and flare days, the most logged types and colours, and the phase table
/// from `SkinStats`. A percentage needs `SkinStats.minimumCycles` cycles with skin logs and
/// `SkinStats.minimumDaysPerPhase` logged days in the phase; otherwise only counts are given.
struct SkinReport: Equatable {
    struct PhaseCount: Equatable {
        let phase: Event.EventType
        /// Days with a skin log in this phase (any area).
        let loggedDays: Int
        /// Of those, days this area flared.
        let flareDays: Int
        let percent: Int?
    }

    struct AreaSummary: Equatable, Identifiable {
        let area: SkinTag.Area
        /// Days with any skin log for this area, Clear included.
        let loggedDays: Int
        /// Days this area had a type other than Clear.
        let flareDays: Int
        /// Up to two, most flare days first.
        let topKinds: [SkinTag.Kind]
        let topColours: [SkinTag.Colour]
        /// One per phase, in `Event.EventType.allCases` order.
        let phases: [PhaseCount]
        var id: String { area.rawValue }
    }

    static let topLimit = 2

    /// Days with a skin log (legacy Other:Acne included).
    let loggedDays: Int
    let cyclesCovered: Int
    let hasPhaseData: Bool
    let areas: [AreaSummary]

    var hasData: Bool { loggedDays > 0 }
}

/// The Sexual activity section: days with `Intimacy:Sex` or `Planning:Intercourse`, each day counted once.
struct SexualActivityReport: Equatable {
    struct CycleCount: Equatable {
        let start: Date
        let days: Int
        /// The running cycle, which has no end yet.
        let isCurrent: Bool
    }

    struct PhaseDays: Equatable {
        let phase: Event.EventType
        let days: Int
    }

    let totalDays: Int
    /// The last `DoctorReport.chartCycles` cycles, oldest first. Empty in Menopause mode.
    let perCycle: [CycleCount]
    /// One per phase, in `Event.EventType.allCases` order.
    let perPhase: [PhaseDays]

    var hasData: Bool { totalDays > 0 }
}

struct DoctorReport: Equatable {
    /// Report options, remembered on the export screen. Both default to on.
    static let includeSkinKey = "doctorReportIncludeSkin"
    static let includeSexualActivityKey = "doctorReportIncludeSexualActivity"

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
    /// nil when the person switched the section off.
    var skin: SkinReport? = nil
    var sexualActivity: SexualActivityReport? = nil
}

enum DoctorReportBuilder {
    static func make(events: [Event], archivedBlocks: [ArchivedDataBlock], mode: TrackingMode,
                     today: Date, calendar: Calendar = .current,
                     includeSkin: Bool = true, includeSexualActivity: Bool = true) -> DoctorReport {
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

        // Skin and sexual activity read what the rest of the report reads: cycle data, or everything in
        // Menopause mode. `SkinStats` takes the phase of a day from cycle data only.
        let optional: (stats: SkinStats, days: [Date: Set<String>])? = {
            guard includeSkin || includeSexualActivity else { return nil }
            let sourceEvents = mode == .menopause ? events : cycleEvents
            let sourceBlocks = mode == .menopause ? archivedBlocks : cycleBlocks
            let stats = SkinStats(events: sourceEvents, archivedBlocks: sourceBlocks, today: today, window: .all, calendar: calendar)
            let days = rawTagsByDay(sourceEvents + sourceBlocks.flatMap { $0.groupedEvents.flatMap(\.events) },
                                    today: today, calendar: calendar)
            return (stats, days)
        }()
        let skinSource = includeSkin ? optional : nil
        let sexSource = includeSexualActivity ? optional : nil

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
            menopause: mode == .menopause ? makeMenopause(events: events, today: today, calendar: calendar) : nil,
            skin: skinSource.map { makeSkin(stats: $0.stats, days: $0.days) },
            sexualActivity: sexSource.map {
                makeSexualActivity(stats: $0.stats, days: $0.days, periodStarts: mode == .menopause ? [] : periodStarts)
            }
        )
    }

    /// Start of day to every tag logged that day, up to and including today.
    static func rawTagsByDay(_ events: [Event], today: Date, calendar: Calendar) -> [Date: Set<String>] {
        let end = calendar.startOfDay(for: today)
        var result: [Date: Set<String>] = [:]
        for event in events {
            let key = calendar.startOfDay(for: event.date)
            guard key <= end else { continue }
            let raws = TagParser.split(event.tags)
            if !raws.isEmpty { result[key, default: []].formUnion(raws) }
        }
        return result
    }

    /// Areas in `SkinStats.rows()` order (flared areas), then areas logged only as Clear, in area order.
    static func makeSkin(stats: SkinStats, days: [Date: Set<String>]) -> SkinReport {
        let skinByDay = days.compactMapValues { raws -> [SkinTag]? in
            let tags = raws.sorted().compactMap(SkinTag.parseAny)
            return tags.isEmpty ? nil : tags
        }
        let rows = stats.rows()
        let flared = rows.map(\.area)
        let clearOnly = SkinTag.Area.allCases.filter { area in
            !flared.contains(area) && skinByDay.values.contains { $0.contains { $0.area == area } }
        }

        let areas = (flared + clearOnly).map { area -> SkinReport.AreaSummary in
            let row = rows.first { $0.area == area }
            var logged = 0, flares = 0
            var kindDays: [SkinTag.Kind: Int] = [:], colourDays: [SkinTag.Colour: Int] = [:]
            for tags in skinByDay.values {
                let here = tags.filter { $0.area == area }
                guard !here.isEmpty else { continue }
                logged += 1
                let flaring = here.filter(\.isFlare)
                guard !flaring.isEmpty else { continue }
                flares += 1
                for kind in Set(flaring.flatMap(\.kinds)) where kind != .clear { kindDays[kind, default: 0] += 1 }
                for colour in Set(flaring.compactMap(\.colour)) { colourDays[colour, default: 0] += 1 }
            }
            let phases = Event.EventType.allCases.map { phase -> SkinReport.PhaseCount in
                let loggedInPhase = stats.loggedDaysByPhase[phase] ?? 0
                let flareInPhase = row?.cells.first { $0.phase == phase }?.flareDays ?? 0
                let percent = stats.hasPhaseData
                    ? SkinStats.percent(flareInPhase, of: loggedInPhase, minimum: SkinStats.minimumDaysPerPhase) : nil
                return SkinReport.PhaseCount(phase: phase, loggedDays: loggedInPhase, flareDays: flareInPhase, percent: percent)
            }
            return SkinReport.AreaSummary(area: area, loggedDays: logged, flareDays: flares,
                                          topKinds: top(kindDays, order: SkinTag.Kind.allCases),
                                          topColours: top(colourDays, order: SkinTag.Colour.allCases),
                                          phases: phases)
        }
        return SkinReport(loggedDays: stats.loggedDays, cyclesCovered: stats.cyclesCovered,
                          hasPhaseData: stats.hasPhaseData, areas: areas)
    }

    /// Most frequent first; ties keep `order`.
    private static func top<T: Hashable>(_ counts: [T: Int], order: [T]) -> [T] {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return counts.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : rank[$0.key, default: 0] < rank[$1.key, default: 0] }
            .prefix(SkinReport.topLimit)
            .map(\.key)
    }

    /// A day with `Intimacy:Sex`, `Planning:Intercourse` or both counts once. A cycle runs from one period start
    /// to the next; days before the first start belong to no cycle.
    static func makeSexualActivity(stats: SkinStats, days: [Date: Set<String>], periodStarts: [Date]) -> SexualActivityReport {
        let sexDays = days.filter { !$0.value.isDisjoint(with: SkinStats.intimacyRaws) }.map(\.key)
        let perPhase = stats.intimacyByPhase().map { SexualActivityReport.PhaseDays(phase: $0.phase, days: $0.flareDays) }
        let perCycle = periodStarts.enumerated().map { index, start -> SexualActivityReport.CycleCount in
            let next = index + 1 < periodStarts.count ? periodStarts[index + 1] : nil
            let count = sexDays.filter { day in day >= start && next.map { day < $0 } ?? true }.count
            return SexualActivityReport.CycleCount(start: start, days: count, isCurrent: next == nil)
        }
        return SexualActivityReport(totalDays: sexDays.count,
                                    perCycle: Array(perCycle.suffix(DoctorReport.chartCycles)),
                                    perPhase: perPhase)
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
