//  TodayHome.swift
//  Pure models behind the Today screen: the moon's phase name for the header, the week strip, the hero
//  headline per mode, and the Log Period plan. No UI here, so every rule is unit tested.

import Foundation

// MARK: - Lunar phase

/// The sky's moon phase for a date, for the header line ("Tue, Oct 20 · Waxing gibbous"). Uses the mean
/// synodic month from a known new moon; good to within about a day, which is all a name needs.
enum LunarPhase: String, CaseIterable {
    case newMoon = "New moon"
    case waxingCrescent = "Waxing crescent"
    case firstQuarter = "First quarter"
    case waxingGibbous = "Waxing gibbous"
    case fullMoon = "Full moon"
    case waningGibbous = "Waning gibbous"
    case lastQuarter = "Last quarter"
    case waningCrescent = "Waning crescent"

    static let synodicMonth = 29.530588853
    /// New moon of 6 January 2000, 18:14 UTC.
    static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    var name: String { rawValue }

    /// Days since the last new moon, 0 up to `synodicMonth`.
    static func age(at date: Date) -> Double {
        let days = date.timeIntervalSince(referenceNewMoon) / 86_400
        let age = days.truncatingRemainder(dividingBy: synodicMonth)
        return age < 0 ? age + synodicMonth : age
    }

    /// The quarters and the new and full moon are named for about a day either side; the rest of the
    /// month is crescent or gibbous.
    static func of(_ date: Date) -> LunarPhase {
        let age = age(at: date)
        let quarter = synodicMonth / 4
        switch age {
        case ..<1:                         return .newMoon
        case ..<(quarter - 1):             return .waxingCrescent
        case ..<(quarter + 1):             return .firstQuarter
        case ..<(2 * quarter - 1):         return .waxingGibbous
        case ..<(2 * quarter + 1):         return .fullMoon
        case ..<(3 * quarter - 1):         return .waningGibbous
        case ..<(3 * quarter + 1):         return .lastQuarter
        case ..<(synodicMonth - 1):        return .waningCrescent
        default:                           return .newMoon
        }
    }
}

// MARK: - Week strip

/// One day of the Today week strip.
struct TodayStripDay: Equatable, Identifiable {
    let date: Date
    /// The logged (or generated) cycle phase that day; nil when there is none.
    let phase: Event.EventType?
    /// A day of the estimated next period that has no logged phase yet (drawn dashed).
    let isPredictedPeriod: Bool
    let isToday: Bool
    /// Menopause only: how many tags were logged that day in Menopause mode.
    let menopauseCount: Int

    var id: Date { date }
}

enum TodayWeekStrip {
    /// The seven days of the week containing `today` (the calendar's first weekday first). Cycle phases come
    /// from cycle events only; the estimated next period (`nextPeriod`, `periodLength` days) is marked on days
    /// without a phase. In Menopause mode no phase or prediction is shown, only how much was logged.
    static func days(events: [Event], today: Date, mode: TrackingMode, nextPeriod: Date?, periodLength: Int,
                     calendar: Calendar = .current) -> [TodayStripDay] {
        let todayStart = calendar.startOfDay(for: today)
        let start = calendar.dateInterval(of: .weekOfYear, for: todayStart)?.start ?? todayStart
        let isMenopause = mode == .menopause

        var phaseByDay: [Date: Event.EventType] = [:]
        var countByDay: [Date: Int] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            if event.effectiveMode == .menopause {
                countByDay[day, default: 0] += TagParser.split(event.tags).count
            } else if phaseByDay[day] == nil {
                phaseByDay[day] = event.eventType
            }
        }

        var predicted = Set<Date>()
        if !isMenopause, let nextPeriod {
            let first = calendar.startOfDay(for: nextPeriod)
            for offset in 0..<max(periodLength, 1) {
                if let d = calendar.date(byAdding: .day, value: offset, to: first) { predicted.insert(d) }
            }
        }

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let phase = isMenopause ? nil : phaseByDay[date]
            return TodayStripDay(date: date, phase: phase,
                                 isPredictedPeriod: phase == nil && predicted.contains(date),
                                 isToday: date == todayStart,
                                 menopauseCount: isMenopause ? (countByDay[date] ?? 0) : 0)
        }
    }
}

// MARK: - Hero

/// What the big ring on Today says, per mode.
struct TodayHero: Equatable {
    enum Action: Equatable {
        case logPeriod
        case logTest
        case logSymptoms

        var title: String {
            switch self {
            case .logPeriod:   return "Log Period"
            case .logTest:     return "Log Test"
            case .logSymptoms: return "Log Symptoms"
            }
        }
    }

    /// Small capitals line, for example "Luteal · Day 26".
    let eyebrow: String
    /// The line above the big number, for example "Period in".
    let lead: String
    /// The big text, for example "3 days".
    let headline: String
    let detail: String?
    let action: Action
    /// True when the numbers are fertility estimates (the screen then shows the birth control line).
    let isFertilityEstimate: Bool

    static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    static func shortDate(_ date: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    static func monthDay(_ date: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// - Parameters:
    ///   - fertileDays: `FertileWindow.days` day keys (Planning).
    ///   - hotFlashes: this week and last week (Menopause).
    static func make(mode: TrackingMode, snapshot: PhaseWidgetSnapshot, fertileDays: Set<String> = [],
                     hotFlashes: (thisWeek: Int, lastWeek: Int) = (0, 0), today: Date,
                     calendar: Calendar = .current) -> TodayHero {
        if mode == .menopause {
            let (now, last) = hotFlashes
            let detail: String
            if now == 0 && last == 0 { detail = "None logged this week or last" }
            else if now < last { detail = "Down from \(last) last week" }
            else if now > last { detail = "Up from \(last) last week" }
            else { detail = "Same as last week" }
            return TodayHero(eyebrow: "This week", lead: "Hot flashes", headline: "\(now)", detail: detail,
                             action: .logSymptoms, isFertilityEstimate: false)
        }

        let action: Action = mode == .planning ? .logTest : .logPeriod
        guard let day = snapshot.cycleDay else {
            return TodayHero(eyebrow: "No active cycle", lead: "Start with", headline: "Day 1",
                             detail: "Log your period when it starts.", action: action, isFertilityEstimate: false)
        }
        let eyebrow = snapshot.phase.map { "\($0.rawValue.capitalized) · Day \(day)" } ?? "Day \(day)"

        if mode == .planning, let fertile = planningHero(eyebrow: eyebrow, snapshot: snapshot,
                                                         fertileDays: fertileDays, today: today, calendar: calendar) {
            return fertile
        }

        if let late = snapshot.overdueDays {
            return TodayHero(eyebrow: eyebrow, lead: "Period is", headline: "\(days(late)) late",
                             detail: "An estimate from your cycle", action: action, isFertilityEstimate: false)
        }
        if let until = snapshot.daysUntilNext {
            let expected = snapshot.nextPeriodDate.map { "Expected \(shortDate($0, calendar: calendar))" }
            if until == 0 {
                return TodayHero(eyebrow: eyebrow, lead: "Period may start", headline: "Today", detail: expected,
                                 action: action, isFertilityEstimate: false)
            }
            return TodayHero(eyebrow: eyebrow, lead: "Period in", headline: days(until), detail: expected,
                             action: action, isFertilityEstimate: false)
        }
        return TodayHero(eyebrow: eyebrow, lead: "Cycle day", headline: "\(day)",
                         detail: snapshot.phase?.displayName, action: action, isFertilityEstimate: false)
    }

    private static func planningHero(eyebrow: String, snapshot: PhaseWidgetSnapshot, fertileDays: Set<String>,
                                     today: Date, calendar: Calendar) -> TodayHero? {
        let todayStart = calendar.startOfDay(for: today)
        if snapshot.isFertileToday {
            let ends = snapshot.fertileEndsIn ?? 0
            return TodayHero(eyebrow: eyebrow, lead: "Fertile window", headline: "Today",
                             detail: ends == 0 ? "Ends today" : "Ends in \(days(ends))",
                             action: .logTest, isFertilityEstimate: true)
        }
        guard let startsIn = snapshot.fertileStartsIn,
              let start = calendar.date(byAdding: .day, value: startsIn, to: todayStart) else { return nil }
        // The window runs from five days before ovulation to the ovulation day: best chances are the
        // ovulation day and the day before it, where both are in the window.
        var windowDays: [Date] = []
        var cursor = start
        while fertileDays.contains(FertileWindow.dayKey(cursor, calendar: calendar)) {
            windowDays.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        var detail: String?
        if windowDays.count >= 2 {
            let peakIndex = min(FertileWindow.daysBeforeOvulation, windowDays.count - 1)
            let a = windowDays[peakIndex - 1], b = windowDays[peakIndex]
            let sameMonth = calendar.component(.month, from: a) == calendar.component(.month, from: b)
            detail = "Best chances around \(monthDay(a, calendar: calendar)) and "
                + (sameMonth ? "\(calendar.component(.day, from: b))" : monthDay(b, calendar: calendar))
        }
        return TodayHero(eyebrow: eyebrow, lead: "Fertile window in", headline: days(startsIn), detail: detail,
                         action: .logTest, isFertilityEstimate: true)
    }
}

// MARK: - Menopause week

enum TodayMenopauseWeek {
    /// Tags logged in Menopause mode on each of the last seven days, oldest first (the last entry is today).
    static func dailyCounts(events: [Event], today: Date, calendar: Calendar = .current) -> [Int] {
        let todayStart = calendar.startOfDay(for: today)
        var counts = Array(repeating: 0, count: 7)
        for event in events where event.effectiveMode == .menopause {
            let day = calendar.startOfDay(for: event.date)
            guard let back = calendar.dateComponents([.day], from: day, to: todayStart).day, (0..<7).contains(back) else { continue }
            counts[6 - back] += TagParser.split(event.tags).count
        }
        return counts
    }
}

// MARK: - Log Period

/// What "Log Period" (on Today and in Cycles) does for a chosen first day, `start`: the cycle so far (days
/// before the start) moves to Past cycles, and a new cycle starts on that day with the same length. Tags
/// already logged on the start day or later are kept on the new cycle's day with the same date (combined,
/// never overwritten), or as their own event when the new cycle has no such day. Menopause entries are never
/// touched. Early in a cycle (`offersMoveStart`) the person can instead move the period start to the chosen
/// day (`moveStart`), so a start logged by mistake does not leave a tiny Past cycle. The start is usually
/// today, but a period that began a few days ago is logged on its real first day (`pickerRange`).
enum PeriodStartPlan {
    struct Result: Equatable {
        /// Cycle events dated before the start, for `ArchivedDataStore.archiveCurrent(events:mode:)`.
        let archive: [Event]
        /// The full new event list, for `EventStore.replaceAll`.
        let events: [Event]

        static func == (l: Result, r: Result) -> Bool {
            l.archive.map(\.id) == r.archive.map(\.id) && l.events.map(\.id) == r.events.map(\.id)
        }
    }

    /// True when today is already the first day of the current cycle, so there is nothing to log.
    static func alreadyStartedToday(snapshot: PhaseWidgetSnapshot) -> Bool {
        snapshot.cycleDay == 1 && snapshot.phase == .menstrual
    }

    static func make(events: [Event], start: Date, cycleLength: Int, calendar: Calendar = .current) -> Result {
        let startDay = calendar.startOfDay(for: start)
        let menopause = events.filter { $0.effectiveMode == .menopause }
        let cycle = events.filter { $0.effectiveMode != .menopause }
        let past = cycle.filter { calendar.startOfDay(for: $0.date) < startDay }.sorted { $0.date < $1.date }
        let carried = cycle.filter { calendar.startOfDay(for: $0.date) >= startDay && !$0.tags.isEmpty }

        let fresh = carryOver(carried, onto: CycleGenerator.events(startDate: startDay, cycleLength: cycleLength),
                              calendar: calendar)
        return Result(archive: past, events: menopause + fresh)
    }

    // MARK: The first day

    /// How far back the first day can be picked.
    static let daysBack = 60
    static let cycleLengthRange = 20...45

    /// The cycle length the sheet starts on: the person's average, else the current cycle's, else 28, within
    /// `cycleLengthRange`.
    static func defaultCycleLength(snapshot: PhaseWidgetSnapshot) -> Int {
        min(max(snapshot.averageCycleLength ?? snapshot.cycleLength ?? 28, cycleLengthRange.lowerBound), cycleLengthRange.upperBound)
    }

    /// The first day of the current cycle (the earliest cycle event), nil with no cycle data.
    static func currentCycleStart(events: [Event], calendar: Calendar = .current) -> Date? {
        events.filter { $0.effectiveMode != .menopause }.map { calendar.startOfDay(for: $0.date) }.min()
    }

    /// The last day of the latest Past cycle (Menopause blocks left out), nil with none.
    static func latestArchivedDay(blocks: [ArchivedDataBlock], calendar: Calendar = .current) -> Date? {
        blocks.filter { $0.effectiveMode != .menopause }
            .flatMap { $0.groupedEvents.flatMap(\.events) }
            .map { calendar.startOfDay(for: $0.date) }
            .max()
    }

    /// The days the first day can be: never after today, at most `daysBack` days ago, and never on or before
    /// the last day of the latest Past cycle, so a new cycle cannot overlap a finished one.
    static func pickerRange(today: Date, blocks: [ArchivedDataBlock], calendar: Calendar = .current) -> ClosedRange<Date> {
        let end = calendar.startOfDay(for: today)
        var floor = calendar.date(byAdding: .day, value: -daysBack, to: end) ?? end
        if let last = latestArchivedDay(blocks: blocks, calendar: calendar),
           let after = calendar.date(byAdding: .day, value: 1, to: last) {
            floor = max(floor, after)
        }
        return min(floor, end)...end
    }

    /// `start` moved into `pickerRange`: a future day becomes today, a day too far back becomes the earliest day.
    static func clampedStart(_ start: Date, today: Date, blocks: [ArchivedDataBlock], calendar: Calendar = .current) -> Date {
        let range = pickerRange(today: today, blocks: blocks, calendar: calendar)
        return min(max(calendar.startOfDay(for: start), range.lowerBound), range.upperBound)
    }

    // MARK: The offer

    /// What the sheet offers for a chosen first day, with the consequence in plain words.
    struct Offer: Equatable {
        enum Action: Equatable, Identifiable {
            case moveStart, startNewCycle
            var id: Self { self }

            var title: String {
                switch self {
                case .moveStart:     return "Move period start to this day"
                case .startNewCycle: return "Start a new cycle"
                }
            }
        }

        /// The choices, main one first; empty when there is nothing to do (the cycle already starts that day).
        let actions: [Action]
        let message: String

        var offersMoveStart: Bool { actions.contains(.moveStart) }
    }

    /// "today", "yesterday" or "Oct 18".
    static func dayWord(_ day: Date, today: Date, calendar: Calendar = .current) -> String {
        let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: today)).day ?? 0
        switch back {
        case 0:  return "today"
        case 1:  return "yesterday"
        default: return TodayHero.monthDay(day, calendar: calendar)
        }
    }

    /// The offer for `start`. With no cycle data the cycle simply starts that day. On the current cycle's first
    /// day there is nothing to do. On day 2 to `moveStartMaxDay` of the current cycle the start can be moved
    /// instead of a new cycle started; on a day before the current start the start moves back; later on, a new
    /// cycle starts and the days before it become a Past cycle.
    static func offer(events: [Event], start: Date, today: Date, calendar: Calendar = .current) -> Offer {
        let startDay = calendar.startOfDay(for: start)
        let word = dayWord(startDay, today: today, calendar: calendar)
        let sentenceWord = word.prefix(1).uppercased() + word.dropFirst()
        guard let cycleStart = currentCycleStart(events: events, calendar: calendar) else {
            return Offer(actions: [.startNewCycle],
                         message: "\(sentenceWord) becomes day 1 of your cycle. Predictions start from it, and tags you "
                            + "logged from that day on stay.")
        }
        let day = (calendar.dateComponents([.day], from: cycleStart, to: startDay).day ?? 0) + 1
        if day == 1 {
            return Offer(actions: [], message: "Your cycle already starts \(word).")
        }
        if day < 1 {
            return Offer(actions: [.moveStart],
                         message: "Your current cycle started \(TodayHero.monthDay(cycleStart, calendar: calendar)). "
                            + "Move its start to \(word): nothing is added to Past cycles and your tags stay on their days.")
        }
        if offersMoveStart(cycleDay: day) {
            let ago = TodayHero.days(day - 1)
            let moves = day == 2 ? "that day moves" : "those \(ago) move"
            return Offer(actions: [.moveStart, .startNewCycle],
                         message: "Your current cycle started on \(TodayHero.monthDay(cycleStart, calendar: calendar)). If that start was a mistake, move it "
                            + "to \(word): nothing is added to Past cycles and your tags stay on their days. If a short "
                            + "cycle really ended, start a new cycle: \(moves) to Past cycles as one cycle.")
        }
        return Offer(actions: [.startNewCycle],
                     message: "\(sentenceWord) becomes day 1 of a new cycle. The days since your last period start move to "
                        + "Past cycles as one finished cycle, and predictions use it. Tags you logged from that day on stay. "
                        + "Picked the wrong day? Log Period again and move the start.")
    }

    // MARK: Carry over

    /// Puts tagged events dated today or later onto the generated days with the same date. Every event of a day
    /// is combined into that day (`EventStore.unionTags`, `Event.mergedIntensity`), keeping the first carried
    /// event's mode. An event whose day the new cycle does not have is kept as it is, on its own day.
    static func carryOver(_ carried: [Event], onto generated: [Event], calendar: Calendar) -> [Event] {
        var fresh = generated
        var extras: [Event] = []
        var modeSet = Set<Int>()
        for old in carried.sorted(by: { $0.date < $1.date }) {
            let day = calendar.startOfDay(for: old.date)
            guard let index = fresh.firstIndex(where: { calendar.startOfDay(for: $0.date) == day }) else {
                extras.append(old)
                continue
            }
            if let unioned = EventStore.unionTags(fresh[index].tags, adding: old.tags) {
                fresh[index].tags = unioned
            }
            fresh[index].tagIntensity = Event.mergedIntensity(fresh[index].tagIntensity, old.tagIntensity)
            if !modeSet.contains(index) {
                fresh[index].mode = old.mode
                modeSet.insert(index)
            }
            fresh[index].pruneIntensities()
        }
        return fresh + extras
    }

    // MARK: Move the period start

    /// Early in a cycle (day 2 to 14) Log Period offers to move the current period start to the chosen day
    /// instead of starting a new cycle, since a cycle that short is most likely a start logged by mistake.
    static let moveStartMaxDay = 14

    static func offersMoveStart(cycleDay: Int?) -> Bool {
        guard let cycleDay else { return false }
        return cycleDay > 1 && cycleDay <= moveStartMaxDay
    }

    struct MoveResult {
        /// The full new event list, for `EventStore.replaceAll`.
        let events: [Event]
        /// The new archive list, for `ArchivedDataStore.replaceAll`; nil when the archive does not change.
        let blocks: [ArchivedDataBlock]?
        /// Tagged days before the start with no cycle before them to join, for `archiveCurrent(events:mode:)`;
        /// empty when there is nothing to keep.
        let newArchive: [Event]
    }

    /// "Move period start to this day": the current cycle starts again on `start` with the same length. The
    /// days before it were really the end of the cycle before, so when the latest Past cycle ends right before
    /// them they join it as late luteal days (its length becomes right, nothing new appears in Past cycles).
    /// With no such cycle, untagged days are dropped and tagged ones are kept (`newArchive`) so no tag is lost.
    /// Tags from the start on carry over as in `make`. Menopause entries are never touched.
    static func moveStart(events: [Event], blocks: [ArchivedDataBlock], start: Date, cycleLength: Int,
                          calendar: Calendar = .current) -> MoveResult {
        let startDay = calendar.startOfDay(for: start)
        let menopause = events.filter { $0.effectiveMode == .menopause }
        let cycle = events.filter { $0.effectiveMode != .menopause }
        let before = cycle.filter { calendar.startOfDay(for: $0.date) < startDay }.sorted { $0.date < $1.date }
        let carried = cycle.filter { calendar.startOfDay(for: $0.date) >= startDay && !$0.tags.isEmpty }
        let fresh = carryOver(carried, onto: CycleGenerator.events(startDate: startDay, cycleLength: cycleLength),
                              calendar: calendar)
        let newEvents = menopause + fresh

        guard let firstBefore = before.first else {
            return MoveResult(events: newEvents, blocks: nil, newArchive: [])
        }
        let tail = before.map { event -> Event in
            var copy = event
            copy.eventType = .luteal
            return copy
        }
        let firstDay = calendar.startOfDay(for: firstBefore.date)
        let latest = blocks.enumerated()
            .filter { $0.element.effectiveMode != .menopause }
            .max { $0.element.date < $1.element.date }
        if let index = latest?.offset, let block = latest?.element,
           let lastDay = block.groupedEvents.flatMap(\.events).map({ calendar.startOfDay(for: $0.date) }).max(),
           let gap = calendar.dateComponents([.day], from: lastDay, to: firstDay).day, (1...2).contains(gap) {
            var grouped = block.groupedEvents
            if let luteal = grouped.firstIndex(where: { $0.eventType == .luteal }) {
                grouped[luteal] = ArchivedDataBlock.PhaseEvents(eventType: .luteal, events: grouped[luteal].events + tail)
            } else {
                grouped.append(ArchivedDataBlock.PhaseEvents(eventType: .luteal, events: tail))
            }
            var newBlocks = blocks
            newBlocks[index] = ArchivedDataBlock(id: block.id, date: block.date, groupedEvents: grouped, mode: block.mode)
            return MoveResult(events: newEvents, blocks: newBlocks, newArchive: [])
        }
        return MoveResult(events: newEvents, blocks: nil, newArchive: before.filter { !$0.tags.isEmpty })
    }
}
