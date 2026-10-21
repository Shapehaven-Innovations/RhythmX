//  InsightFacts.swift
//  The facts behind the daily insights: small counts and labels computed from the stores for one day.
//  This is the only input a writer (template or the on-device model) ever sees, so it never holds dates,
//  notes, typed custom tags, medication tags or raw "Category:Value" strings.
//  Cycle and Planning facts come from cycle data only (Menopause entries never shape them); Menopause facts
//  carry no phase, cycle day, period estimate or fertility.

import Foundation

struct InsightFacts: Codable, Equatable {
    /// A library tag's display label and how often it was logged.
    struct TagCount: Codable, Equatable {
        let label: String
        let count: Int
    }

    /// The top pattern finding for the mode: its tag label and one plain sentence with its evidence.
    struct PatternFact: Codable, Equatable {
        let label: String
        let sentence: String
    }

    /// Planning's fertility estimate for the day (`PlanningInsights.Level`).
    enum FertileLevel: String, Codable, CaseIterable {
        case low, rising, high, peak
    }

    let mode: TrackingMode
    let phase: Event.EventType?
    let cycleDay: Int?
    /// Days until the estimated next period; nil when unknown or late.
    let daysUntilPeriod: Int?
    /// Days past the estimated start; nil when not late.
    let periodLateDays: Int?
    /// Planning only.
    let fertileLevel: FertileLevel?
    /// The most logged library tags over the last `recentDays` days in this mode, most first.
    let recentTags: [TagCount]
    /// Tags logged today in this mode.
    let tagsLoggedToday: Int
    let pattern: PatternFact?
    /// Menopause only. Whole months since the last logged period; nil without one.
    let monthsSinceLastPeriod: Int?
    /// Menopause only.
    let hotFlashesThisWeek: Int?
    let hotFlashesLastWeek: Int?
    /// Menopause only. Average hours asleep over the last 7 nights from Apple Health, to one decimal.
    let sleepAverageHours: Double?

    static let recentDays = 14
    static let maxRecentTags = 3

    init(mode: TrackingMode, phase: Event.EventType? = nil, cycleDay: Int? = nil, daysUntilPeriod: Int? = nil,
         periodLateDays: Int? = nil, fertileLevel: FertileLevel? = nil, recentTags: [TagCount] = [],
         tagsLoggedToday: Int = 0, pattern: PatternFact? = nil, monthsSinceLastPeriod: Int? = nil,
         hotFlashesThisWeek: Int? = nil, hotFlashesLastWeek: Int? = nil, sleepAverageHours: Double? = nil) {
        self.mode = mode
        self.phase = phase
        self.cycleDay = cycleDay
        self.daysUntilPeriod = daysUntilPeriod
        self.periodLateDays = periodLateDays
        self.fertileLevel = fertileLevel
        self.recentTags = recentTags
        self.tagsLoggedToday = tagsLoggedToday
        self.pattern = pattern
        self.monthsSinceLastPeriod = monthsSinceLastPeriod
        self.hotFlashesThisWeek = hotFlashesThisWeek
        self.hotFlashesLastWeek = hotFlashesLastWeek
        self.sleepAverageHours = sleepAverageHours
    }

    // MARK: - Building

    /// - Parameters:
    ///   - events: every live event; the mode filter is applied here.
    ///   - sleepSummary: `HealthSync.importedSleep` (empty when reading sleep is off). Menopause only.
    static func make(events: [Event], archivedBlocks: [ArchivedDataBlock], mode: TrackingMode, today: Date,
                     fertileOverrides: FertileOverrides = FertileOverrides(),
                     sleepSummary: [Date: TimeInterval] = [:], calendar: Calendar = .current) -> InsightFacts {
        let isMenopause = mode == .menopause
        let modeEvents = events.filter { ($0.effectiveMode == .menopause) == isMenopause }
        let modeBlocks = archivedBlocks.filter { ($0.effectiveMode == .menopause) == isMenopause }

        let recent = recentTags(events: modeEvents, blocks: modeBlocks, today: today, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        let loggedToday = modeEvents
            .filter { calendar.startOfDay(for: $0.date) == todayStart }
            .reduce(0) { $0 + TagParser.split($1.tags).count }
        let pattern = PatternFinder.findings(events: modeEvents, archivedBlocks: modeBlocks, mode: mode,
                                             today: today, calendar: calendar)
            .first { isSurfaceable(raw: $0.tag) }
            .map { PatternFact(label: TagParser.label(for: $0.tag), sentence: "\($0.sentence), in \($0.evidence).") }

        if isMenopause {
            // Same numbers as the Menopause Insights screen, which reads every event (the last period is a
            // cycle period day); nothing here goes back into cycle facts.
            let menopause = MenopauseInsights.make(events: events, today: today, calendar: calendar)
            let perWeek = menopause.hotFlashesPerWeek
            let sleep = SleepInsights.make(summary: sleepSummary, today: today, calendar: calendar).averageHours
            return InsightFacts(
                mode: mode,
                recentTags: recent,
                tagsLoggedToday: loggedToday,
                pattern: pattern,
                monthsSinceLastPeriod: menopause.lastPeriod == nil ? nil : menopause.monthsSinceLastPeriod,
                hotFlashesThisWeek: perWeek.last ?? 0,
                hotFlashesLastWeek: perWeek.count >= 2 ? perWeek[perWeek.count - 2] : 0,
                sleepAverageHours: sleep.map { ($0 * 10).rounded() / 10 }
            )
        }

        let snapshot = PhaseWidgetSnapshot.make(events: modeEvents, archived: modeBlocks, today: today,
                                                fertileOverrides: fertileOverrides)
        var fertile: FertileLevel?
        if mode == .planning {
            switch PlanningInsights.make(events: modeEvents, overrides: fertileOverrides, today: today, calendar: calendar).fertilityLevel {
            case .low:    fertile = .low
            case .rising: fertile = .rising
            case .high:   fertile = .high
            case .peak:   fertile = .peak
            }
        }
        let hasDay = snapshot.cycleDay != nil
        return InsightFacts(
            mode: mode,
            phase: hasDay ? snapshot.phase : nil,
            cycleDay: snapshot.cycleDay,
            daysUntilPeriod: snapshot.daysUntilNext,
            periodLateDays: snapshot.overdueDays,
            fertileLevel: fertile,
            recentTags: recent,
            tagsLoggedToday: loggedToday,
            pattern: pattern
        )
    }

    /// Library tags only, never Medication: typed custom text and medicines stay out of every writer's input.
    static func isSurfaceable(raw: String) -> Bool {
        let pick = TagFormLogic.pick(fromRaw: raw)
        guard pick.category != .medication else { return false }
        return (TagLibrary.tags[pick.category] ?? []).contains(pick.value)
    }

    private static func recentTags(events: [Event], blocks: [ArchivedDataBlock], today: Date,
                                   calendar: Calendar) -> [TagCount] {
        let todayStart = calendar.startOfDay(for: today)
        let earliest = calendar.date(byAdding: .day, value: -(recentDays - 1), to: todayStart) ?? todayStart
        var seen = Set<String>()
        var counts: [String: Int] = [:]
        for event in events + blocks.flatMap({ $0.groupedEvents.flatMap(\.events) }) {
            guard seen.insert(event.id).inserted else { continue }
            let day = calendar.startOfDay(for: event.date)
            guard day >= earliest, day <= todayStart else { continue }
            for raw in TagParser.split(event.tags) where isSurfaceable(raw: raw) {
                counts[TagParser.label(for: raw), default: 0] += 1
            }
        }
        return counts
            .map { TagCount(label: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
            .prefix(maxRecentTags)
            .map { $0 }
    }

    // MARK: - What a writer may say

    /// Tag labels a written text may name.
    var allowedTagLabels: Set<String> {
        Set(recentTags.map(\.label) + [pattern?.label].compactMap { $0 })
    }

    /// Numbers a written text may use, as written ("24", "6.7").
    var allowedNumbers: Set<String> {
        var numbers: [Int] = recentTags.map(\.count) + [tagsLoggedToday]
        numbers += [cycleDay, daysUntilPeriod, periodLateDays, monthsSinceLastPeriod,
                    hotFlashesThisWeek, hotFlashesLastWeek].compactMap { $0 }
        var result = Set(numbers.map(String.init))
        if let sentence = pattern?.sentence { result.formUnion(InsightTextValidator.numbers(in: sentence)) }
        if let sleep = sleepAverageHours {
            result.insert(SleepInsights.rounded(sleep))
            result.insert(String(Int(sleep.rounded())))
        }
        return result
    }
}
