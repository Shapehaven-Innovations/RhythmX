//  PatternFinder.swift
//  Deterministic pattern finding behind the Patterns segment of the Tags tab. No AI, no UI.
//
//  Cycle and Planning look at the last 6 cycles: archived blocks that are not Menopause, oldest first,
//  plus the live cycle when it has at least one tag. Menopause looks at the last 8 weeks of menopause
//  events, live and archived. Repeated tags count each occurrence.

import Foundation

/// One heatmap cell: a phase column (Cycle, Planning) or a week column (Menopause, oldest first).
struct TagPhaseCell: Equatable, Hashable {
    let phase: Event.EventType?
    let weekIndex: Int?
    let count: Int
}

/// One heatmap row: a raw tag with four phase cells, or eight week cells in Menopause.
struct TagPhaseRow: Equatable, Identifiable, Hashable {
    let id: String
    let tag: String
    let cells: [TagPhaseCell]

    init(tag: String, cells: [TagPhaseCell]) {
        self.id = tag
        self.tag = tag
        self.cells = cells
    }

    var label: String { TagParser.label(for: tag) }
    var total: Int { cells.reduce(0) { $0 + $1.count } }
}

/// How often a tag was logged on one cycle day, summed over the cycles, with the phase that day usually falls in.
struct TagCycleDayCount: Equatable, Identifiable {
    let id: Int
    let cycleDay: Int
    let count: Int
    let phase: Event.EventType?

    init(cycleDay: Int, count: Int, phase: Event.EventType?) {
        self.id = cycleDay
        self.cycleDay = cycleDay
        self.count = count
        self.phase = phase
    }
}

/// A plain-language finding with its evidence count. The sentence and evidence are the only text that
/// may reach the on-device summary; they never carry dates, notes or raw "Category:Value" strings.
struct PatternFinding: Equatable, Identifiable {
    let id: String
    let sentence: String
    let evidence: String
    let tag: String
}

/// The typical span of one phase across the cycles considered, in cycle days.
struct PhaseBand: Equatable, Identifiable {
    let phase: Event.EventType
    let startDay: Int
    let endDay: Int
    var id: String { phase.rawValue }
}

enum PatternFinder {
    static let maxCycles = 6
    static let weeks = 8
    /// A finding needs evidence in at least this many cycles (weeks in Menopause).
    static let minimumCycles = 3
    static let maxRows = 8
    static let maxFindings = 3
    /// The widest run of cycle days a finding may describe.
    static let maxWindowDays = 5

    // MARK: - Public API

    static func heatmap(events: [Event], archivedBlocks: [ArchivedDataBlock], mode: TrackingMode,
                        today: Date = Date(), calendar: Calendar = .current) -> [TagPhaseRow] {
        switch mode {
        case .cycle, .planning:
            var counts: [String: [Event.EventType: Int]] = [:]
            for occurrence in occurrences(in: cycles(events: events, archivedBlocks: archivedBlocks, calendar: calendar)) {
                counts[occurrence.tag, default: [:]][occurrence.phase, default: 0] += 1
            }
            return rows(from: counts.mapValues { byPhase in
                Event.EventType.allCases.map { TagPhaseCell(phase: $0, weekIndex: nil, count: byPhase[$0] ?? 0) }
            })
        case .menopause:
            var counts: [String: [Int]] = [:]
            for occurrence in weekOccurrences(events: events, archivedBlocks: archivedBlocks, today: today, calendar: calendar) {
                counts[occurrence.tag, default: Array(repeating: 0, count: weeks)][occurrence.weekIndex] += 1
            }
            return rows(from: counts.mapValues { byWeek in
                byWeek.enumerated().map { TagPhaseCell(phase: nil, weekIndex: $0.offset, count: $0.element) }
            })
        }
    }

    static func cycleDayCounts(tag: String, events: [Event], archivedBlocks: [ArchivedDataBlock],
                               calendar: Calendar = .current) -> [TagCycleDayCount] {
        var counts: [Int: Int] = [:]
        var phases: [Int: [Event.EventType: Int]] = [:]
        for occurrence in occurrences(in: cycles(events: events, archivedBlocks: archivedBlocks, calendar: calendar)) where occurrence.tag == tag {
            counts[occurrence.day, default: 0] += 1
            phases[occurrence.day, default: [:]][occurrence.phase, default: 0] += 1
        }
        return counts.keys.sorted().map { day in
            TagCycleDayCount(cycleDay: day, count: counts[day] ?? 0, phase: dominantPhase(phases[day] ?? [:]))
        }
    }

    static func findings(events: [Event], archivedBlocks: [ArchivedDataBlock], mode: TrackingMode,
                         today: Date = Date(), calendar: Calendar = .current) -> [PatternFinding] {
        Array(allFindings(events: events, archivedBlocks: archivedBlocks, mode: mode, today: today, calendar: calendar).prefix(maxFindings))
    }

    /// The finding for one tag, whether or not it made the top three. Nil without enough evidence.
    static func finding(for tag: String, events: [Event], archivedBlocks: [ArchivedDataBlock], mode: TrackingMode,
                        today: Date = Date(), calendar: Calendar = .current) -> PatternFinding? {
        allFindings(events: events, archivedBlocks: archivedBlocks, mode: mode, today: today, calendar: calendar)
            .first { $0.tag == tag }
    }

    /// Typical start and end day of each phase over the cycles considered; phases with no events are left out.
    static func phaseBands(events: [Event], archivedBlocks: [ArchivedDataBlock], calendar: Calendar = .current) -> [PhaseBand] {
        var starts: [Event.EventType: [Int]] = [:]
        var ends: [Event.EventType: [Int]] = [:]
        for cycle in cycles(events: events, archivedBlocks: archivedBlocks, calendar: calendar) {
            for phase in Event.EventType.allCases {
                let days = cycle.filter { $0.event.eventType == phase }.map(\.day)
                guard let first = days.min(), let last = days.max() else { continue }
                starts[phase, default: []].append(first)
                ends[phase, default: []].append(last)
            }
        }
        return Event.EventType.allCases.compactMap { phase in
            guard let s = starts[phase], let e = ends[phase], !s.isEmpty else { return nil }
            return PhaseBand(phase: phase, startDay: average(s), endDay: average(e))
        }
    }

    /// Cycles the finder can see (at most `maxCycles`): used by the empty state.
    static func cyclesAvailable(events: [Event], archivedBlocks: [ArchivedDataBlock], calendar: Calendar = .current) -> Int {
        cycles(events: events, archivedBlocks: archivedBlocks, calendar: calendar).count
    }

    /// Weeks of the last 8 with at least one menopause tag: the Menopause counterpart of `cyclesAvailable`.
    static func weeksAvailable(events: [Event], archivedBlocks: [ArchivedDataBlock],
                               today: Date = Date(), calendar: Calendar = .current) -> Int {
        Set(weekOccurrences(events: events, archivedBlocks: archivedBlocks, today: today, calendar: calendar).map(\.weekIndex)).count
    }

    /// The average level (1 light to 3 heavy) of `tag` over the same events the heatmap looks at: the last
    /// `maxCycles` cycles in Cycle and Planning, the last `weeks` weeks of menopause events in Menopause.
    /// Each event holding the tag counts once; logs without a level are left out. Nil when none has a level.
    /// Intensity never changes any count above.
    static func averageIntensity(tag: String, events: [Event], archivedBlocks: [ArchivedDataBlock], mode: TrackingMode,
                                 today: Date = Date(), calendar: Calendar = .current) -> Double? {
        let considered: [Event]
        switch mode {
        case .cycle, .planning:
            considered = cycles(events: events, archivedBlocks: archivedBlocks, calendar: calendar).flatMap { $0.map(\.event) }
        case .menopause:
            let today = calendar.startOfDay(for: today)
            let archived = archivedBlocks.filter { $0.effectiveMode == .menopause }.flatMap { $0.groupedEvents.flatMap(\.events) }
            considered = (events + archived).filter { event in
                guard event.effectiveMode == .menopause,
                      let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: event.date), to: today).day
                else { return false }
                return daysAgo >= 0 && daysAgo / 7 < weeks
            }
        }
        let levels = considered
            .filter { TagParser.split($0.tags).contains(tag) }
            .compactMap { $0.intensity(for: tag)?.rawValue }
        guard !levels.isEmpty else { return nil }
        return Double(levels.reduce(0, +)) / Double(levels.count)
    }

    /// How many more cycles (or weeks) are needed before a finding is possible.
    static func cyclesNeeded(available: Int) -> Int {
        max(0, minimumCycles - available)
    }

    // MARK: - Cycles

    typealias DayEvent = (day: Int, event: Event)

    /// The last `maxCycles` cycles, oldest first. Each event carries its cycle day (1 = the cycle's first day).
    static func cycles(events: [Event], archivedBlocks: [ArchivedDataBlock], calendar: Calendar = .current) -> [[DayEvent]] {
        var result: [[Event]] = archivedBlocks
            .filter { $0.effectiveMode != .menopause }
            .sorted { $0.date < $1.date }
            .map { block in block.groupedEvents.flatMap(\.events).filter { $0.effectiveMode != .menopause } }
            .filter { !$0.isEmpty }

        let live = events.filter { $0.effectiveMode != .menopause }
        if live.contains(where: { !TagParser.split($0.tags).isEmpty }) {
            result.append(live)
        }

        return result.suffix(maxCycles).map { cycleEvents in
            let sorted = cycleEvents.sorted { $0.date < $1.date }
            guard let anchor = sorted.first.map({ calendar.startOfDay(for: $0.date) }) else { return [] }
            return sorted.map { event in
                let day = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: event.date)).day ?? 0
                return (day: day + 1, event: event)
            }
        }
    }

    private struct Occurrence {
        let tag: String
        let cycleIndex: Int
        let day: Int
        let phase: Event.EventType
    }

    private static func occurrences(in cycles: [[DayEvent]]) -> [Occurrence] {
        var result: [Occurrence] = []
        for (index, cycle) in cycles.enumerated() {
            for entry in cycle {
                for raw in TagParser.split(entry.event.tags) {
                    result.append(Occurrence(tag: raw, cycleIndex: index, day: entry.day, phase: entry.event.eventType))
                }
            }
        }
        return result
    }

    // MARK: - Weeks (Menopause)

    private struct WeekOccurrence {
        let tag: String
        /// 0 is the oldest of the 8 weeks, 7 the current one.
        let weekIndex: Int
    }

    private static func weekOccurrences(events: [Event], archivedBlocks: [ArchivedDataBlock],
                                        today: Date, calendar: Calendar) -> [WeekOccurrence] {
        let today = calendar.startOfDay(for: today)
        let archived = archivedBlocks
            .filter { $0.effectiveMode == .menopause }
            .flatMap { $0.groupedEvents.flatMap(\.events) }
        let menopauseEvents = (events + archived).filter { $0.effectiveMode == .menopause }

        var result: [WeekOccurrence] = []
        for event in menopauseEvents {
            let day = calendar.startOfDay(for: event.date)
            guard let daysAgo = calendar.dateComponents([.day], from: day, to: today).day, daysAgo >= 0 else { continue }
            let week = daysAgo / 7
            guard week < weeks else { continue }
            for raw in TagParser.split(event.tags) {
                result.append(WeekOccurrence(tag: raw, weekIndex: weeks - 1 - week))
            }
        }
        return result
    }

    // MARK: - Findings

    private static func allFindings(events: [Event], archivedBlocks: [ArchivedDataBlock], mode: TrackingMode,
                                    today: Date, calendar: Calendar) -> [PatternFinding] {
        switch mode {
        case .cycle, .planning:
            return cycleFindings(in: cycles(events: events, archivedBlocks: archivedBlocks, calendar: calendar))
        case .menopause:
            return weekFindings(weekOccurrences(events: events, archivedBlocks: archivedBlocks, today: today, calendar: calendar))
        }
    }

    private struct Candidate {
        let finding: PatternFinding
        let cyclesHit: Int
        let coverage: Double
        let width: Int
        let label: String
    }

    private static func cycleFindings(in cycles: [[DayEvent]]) -> [PatternFinding] {
        guard cycles.count >= minimumCycles else { return [] }
        let all = occurrences(in: cycles)
        let byTag = Dictionary(grouping: all, by: \.tag)
        let maxDay = all.map(\.day).max() ?? 0
        guard maxDay > 0 else { return [] }

        var candidates: [Candidate] = []
        for (tag, occurrences) in byTag {
            var best: (start: Int, width: Int, hit: Int, coverage: Double)?
            for width in 1...maxWindowDays where width <= maxDay {
                for start in 1...(maxDay - width + 1) {
                    let end = start + width - 1
                    let inside = occurrences.filter { $0.day >= start && $0.day <= end }
                    let hit = Set(inside.map(\.cycleIndex)).count
                    let coverage = Double(inside.count) / Double(occurrences.count)
                    if let current = best {
                        let better = hit > current.hit
                            || (hit == current.hit && coverage > current.coverage)
                            || (hit == current.hit && coverage == current.coverage && width < current.width)
                        guard better else { continue }
                    }
                    best = (start, width, hit, coverage)
                }
            }
            guard let window = best, window.hit >= minimumCycles else { continue }

            let end = window.start + window.width - 1
            let inside = occurrences.filter { $0.day >= window.start && $0.day <= end }
            var phaseCounts: [Event.EventType: Int] = [:]
            for occurrence in inside { phaseCounts[occurrence.phase, default: 0] += 1 }
            let phase = dominantPhase(phaseCounts) ?? .menstrual
            let label = TagParser.label(for: tag)
            let days = window.width == 1 ? "day \(window.start)" : "days \(window.start) to \(end)"
            let finding = PatternFinding(
                id: tag,
                sentence: "\(label) came up on \(days), in your \(phase.rawValue) phase",
                evidence: "\(window.hit) of your last \(cycles.count) cycles",
                tag: tag
            )
            candidates.append(Candidate(finding: finding, cyclesHit: window.hit, coverage: window.coverage,
                                        width: window.width, label: label))
        }

        return candidates.sorted { a, b in
            if a.cyclesHit != b.cyclesHit { return a.cyclesHit > b.cyclesHit }
            if a.coverage != b.coverage { return a.coverage > b.coverage }
            if a.width != b.width { return a.width < b.width }
            return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
        }.map(\.finding)
    }

    private static func weekFindings(_ occurrences: [WeekOccurrence]) -> [PatternFinding] {
        let byTag = Dictionary(grouping: occurrences, by: \.tag)
        struct WeekCandidate { let finding: PatternFinding; let weeksHit: Int; let total: Int; let label: String }

        let candidates: [WeekCandidate] = byTag.compactMap { tag, occurrences in
            let weeksHit = Set(occurrences.map(\.weekIndex)).count
            guard weeksHit >= minimumCycles else { return nil }
            let label = TagParser.label(for: tag)
            let times = occurrences.count == 1 ? "once" : "\(occurrences.count) times"
            let finding = PatternFinding(
                id: tag,
                sentence: "\(label) came up \(times)",
                evidence: "\(weeksHit) of the last \(weeks) weeks",
                tag: tag
            )
            return WeekCandidate(finding: finding, weeksHit: weeksHit, total: occurrences.count, label: label)
        }

        return candidates.sorted { a, b in
            if a.weeksHit != b.weeksHit { return a.weeksHit > b.weeksHit }
            if a.total != b.total { return a.total > b.total }
            return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
        }.map(\.finding)
    }

    // MARK: - Helpers

    /// Rows sorted most frequent first, then by label, capped at `maxRows`.
    private static func rows(from cellsByTag: [String: [TagPhaseCell]]) -> [TagPhaseRow] {
        cellsByTag
            .map { TagPhaseRow(tag: $0.key, cells: $0.value) }
            .filter { $0.total > 0 }
            .sorted { a, b in
                if a.total != b.total { return a.total > b.total }
                return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
            }
            .prefix(maxRows)
            .map { $0 }
    }

    /// The most frequent phase; ties go to the earlier phase in cycle order.
    private static func dominantPhase(_ counts: [Event.EventType: Int]) -> Event.EventType? {
        Event.EventType.allCases
            .filter { (counts[$0] ?? 0) > 0 }
            .max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }

    private static func average(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
