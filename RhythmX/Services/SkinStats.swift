//  SkinStats.swift
//  Skin flare percentages by cycle phase and body area. Pure; built from value copies.
//
//  Denominator is logged days (days with a skin log or the legacy Other:Acne), never phase days.
//  The phase of a day comes from CalendarPhaseLookup.phaseByDay only, so menopause events never
//  supply a phase.

import Foundation

struct SkinStats {
    enum Window: Equatable, Hashable {
        case days(Int), all
        static let thirty = Window.days(30)
        static let ninety = Window.days(90)
    }

    enum KindFilter: String, CaseIterable, Identifiable {
        case acneBreakout = "Acne & breakout", dryFlaky = "Dry & flaky", oily = "Oily", irritated = "Irritated"

        var id: String { rawValue }

        var kinds: Set<SkinTag.Kind> {
            switch self {
            case .acneBreakout: return [.acne, .breakout]
            case .dryFlaky:     return [.dry, .flaky]
            case .oily:         return [.oily]
            case .irritated:    return [.irritated]
            }
        }

        var verb: String {
            switch self {
            case .acneBreakout: return "breaks out"
            case .dryFlaky:     return "is dry"
            case .oily:         return "is oily"
            case .irritated:    return "is irritated"
            }
        }
    }

    struct PhaseCell: Equatable {
        let phase: Event.EventType
        let loggedDays: Int
        let flareDays: Int
        /// nil when `loggedDays < minimumDaysPerPhase`.
        var percent: Int? { SkinStats.percent(flareDays, of: loggedDays, minimum: SkinStats.minimumDaysPerPhase) }
    }

    struct AreaRow: Equatable, Identifiable {
        let area: SkinTag.Area
        let cells: [PhaseCell]
        let peak: Set<Event.EventType>
        let topKind: SkinTag.Kind?
        let topColour: SkinTag.Colour?
        var id: String { area.rawValue }
        var maxPercent: Int { cells.compactMap(\.percent).max() ?? 0 }
    }

    static let minimumDaysPerPhase = 3
    static let minimumCycles = 2
    static let minimumDaysForBody = 3
    static let minimumDaysForComparison = 5
    static let bannedWords = ["hormone", "hormonal", "progesterone", "estrogen", "oestrogen", "because", "cause", "caused"]

    static let intimacyRaws: Set<String> = ["Intimacy:Sex", "Planning:Intercourse"]

    let window: Window
    let kinds: Set<SkinTag.Kind>?

    /// Start-of-day key to the day's phase (cycle and planning events only).
    private let phaseByDay: [Date: Event.EventType]
    /// Days in the window with a skin log, to the parsed skin tags of that day (legacy acne as Face/Acne).
    private let skinByDay: [Date: [SkinTag]]
    /// Days in the window with any tag at all, to the raw tags of that day.
    private let tagsByDay: [Date: Set<String>]

    let loggedDays: Int
    let loggedDaysByPhase: [Event.EventType: Int]
    let cyclesCovered: Int
    var hasPhaseData: Bool { cyclesCovered >= Self.minimumCycles }

    init(events: [Event], archivedBlocks: [ArchivedDataBlock], today: Date, window: Window,
         kinds: Set<SkinTag.Kind>? = nil, calendar: Calendar = .current) {
        self.window = window
        self.kinds = kinds

        // Pass 1: one definition of the phase of a day.
        let phases = CalendarPhaseLookup.phaseByDay(events: events, archivedBlocks: archivedBlocks, calendar: calendar)
        phaseByDay = phases

        // Pass 2: bucket tags by day inside the window. Tags from every event count (menopause too);
        // only the phase lookup excludes menopause.
        let end = calendar.startOfDay(for: today)
        let start: Date? = {
            if case .days(let n) = window { return calendar.date(byAdding: .day, value: -n, to: end) }
            return nil
        }()
        var tags: [Date: Set<String>] = [:]
        for event in events + archivedBlocks.flatMap({ $0.groupedEvents.flatMap(\.events) }) {
            let key = calendar.startOfDay(for: event.date)
            guard key <= end, start.map({ key > $0 }) ?? true else { continue }
            let raws = TagParser.split(event.tags)
            guard !raws.isEmpty else { continue }
            tags[key, default: []].formUnion(raws)
        }
        tagsByDay = tags

        var skin: [Date: [SkinTag]] = [:]
        for (day, raws) in tags {
            let parsed = raws.sorted().compactMap(SkinTag.parseAny)
            if !parsed.isEmpty { skin[day] = parsed }
        }
        skinByDay = skin

        loggedDays = skin.count
        var byPhase: [Event.EventType: Int] = [:]
        for day in skin.keys { if let p = phases[day] { byPhase[p, default: 0] += 1 } }
        loggedDaysByPhase = byPhase
        cyclesCovered = Self.cyclesCovered(loggedDays: Set(skin.keys), events: events,
                                           archivedBlocks: archivedBlocks, calendar: calendar)
    }

    // MARK: Rules

    static func percent(_ part: Int, of whole: Int, minimum: Int) -> Int? {
        guard whole >= minimum, whole > 0 else { return nil }
        return Int((100.0 * Double(part) / Double(whole)).rounded())
    }

    /// Flare match for one tag on one area: kinds intersect the filter, or any non-Clear kind when no filter.
    private func matches(_ tag: SkinTag, area: SkinTag.Area) -> Bool {
        guard tag.area == area else { return false }
        guard let kinds else { return tag.isFlare }
        return !Set(tag.kinds).subtracting([.clear]).isDisjoint(with: kinds)
    }

    private func isFlareDay(_ day: Date, area: SkinTag.Area) -> Bool {
        skinByDay[day]?.contains { matches($0, area: area) } ?? false
    }

    private func cells(area: SkinTag.Area) -> [PhaseCell] {
        Event.EventType.allCases.map { phase in
            let days = skinByDay.keys.filter { phaseByDay[$0] == phase }
            return PhaseCell(phase: phase, loggedDays: days.count,
                             flareDays: days.filter { isFlareDay($0, area: area) }.count)
        }
    }

    private static func peak(of cells: [PhaseCell]) -> Set<Event.EventType> {
        let valued = cells.filter { $0.percent != nil }
        guard valued.count >= 2, let maximum = valued.compactMap(\.percent).max(), maximum > 0 else { return [] }
        return Set(valued.filter { $0.percent == maximum }.map(\.phase))
    }

    private func row(area: SkinTag.Area) -> AreaRow {
        let cells = cells(area: area)
        let peak = Self.peak(of: cells)
        let flareDays = skinByDay.keys.filter { isFlareDay($0, area: area) }
        let source = peak.isEmpty ? flareDays : flareDays.filter { phaseByDay[$0].map(peak.contains) ?? false }
        var kindCount: [SkinTag.Kind: Int] = [:]
        var colourCount: [SkinTag.Colour: Int] = [:]
        for day in source {
            let tags = skinByDay[day, default: []].filter { matches($0, area: area) }
            for kind in Set(tags.flatMap(\.kinds)) where kind != .clear { kindCount[kind, default: 0] += 1 }
            for colour in Set(tags.compactMap(\.colour)) { colourCount[colour, default: 0] += 1 }
        }
        return AreaRow(area: area, cells: cells, peak: peak,
                       topKind: Self.mostFrequent(kindCount, order: SkinTag.Kind.allCases),
                       topColour: Self.mostFrequent(colourCount, order: SkinTag.Colour.allCases))
    }

    private static func mostFrequent<T: Hashable>(_ counts: [T: Int], order: [T]) -> T? {
        var best: T?
        var bestCount = 0
        for item in order { if let c = counts[item], c > bestCount { best = item; bestCount = c } }
        return best
    }

    private func overallRatio(area: SkinTag.Area) -> Double {
        guard loggedDays > 0 else { return 0 }
        return Double(skinByDay.keys.filter { isFlareDay($0, area: area) }.count) / Double(loggedDays)
    }

    // MARK: Public queries

    /// Areas with at least one flare day in the window, sorted by highest phase percentage, then overall
    /// percentage, then area order; Face (unspecified) last.
    func rows() -> [AreaRow] {
        let areas = SkinTag.Area.allCases.filter { area in skinByDay.keys.contains { isFlareDay($0, area: area) } }
        let order = Dictionary(uniqueKeysWithValues: SkinTag.Area.allCases.enumerated().map { ($1, $0) })
        return areas.map { (row: row(area: $0), ratio: overallRatio(area: $0)) }
            .sorted { a, b in
                let aFace = a.row.area == .face, bFace = b.row.area == .face
                if aFace != bFace { return bFace }
                if a.row.maxPercent != b.row.maxPercent { return a.row.maxPercent > b.row.maxPercent }
                if a.ratio != b.ratio { return a.ratio > b.ratio }
                return order[a.row.area, default: 0] < order[b.row.area, default: 0]
            }
            .map(\.row)
    }

    /// Every area's percentage for the body graph. A phase uses that phase's logged days and
    /// `minimumDaysPerPhase`; nil phase uses all logged days and `minimumDaysForBody`. nil value = not enough days.
    func percentByArea(phase: Event.EventType?) -> [SkinTag.Area: Int?] {
        let days = phase.map { p in skinByDay.keys.filter { phaseByDay[$0] == p } } ?? Array(skinByDay.keys)
        let minimum = phase == nil ? Self.minimumDaysForBody : Self.minimumDaysPerPhase
        var result: [SkinTag.Area: Int?] = [:]
        for area in SkinTag.Area.allCases {
            result[area] = .some(Self.percent(days.filter { isFlareDay($0, area: area) }.count, of: days.count, minimum: minimum))
        }
        return result
    }

    func topAreas(limit: Int = 3) -> [AreaRow] { Array(rows().prefix(limit)) }

    /// The Today card sentence. Template only; phase and area words are lowercase.
    func sentence(todayPhase: Event.EventType?, cycleDay: Int?, mode: TrackingMode) -> String {
        if mode == .menopause {
            let areas = loggedDays >= Self.minimumDaysForBody ? topAreas(limit: 2).map(\.area) : []
            guard !areas.isEmpty else {
                return "Log your skin on a few days and this card shows where it has flared most."
            }
            let verb = areas.count == 1 ? "has" : "have"
            return "Your \(Self.areaList(areas)) \(verb) flared most \(windowPhrase)."
        }

        guard hasPhaseData else {
            return "Log your skin through two cycles and this card shows where it tends to flare. "
                + "\(min(cyclesCovered, Self.minimumCycles)) of \(Self.minimumCycles) so far."
        }

        var parts: [String] = []
        let all = rows()
        if let first = all.first(where: { !$0.peak.isEmpty }),
           let phase = Event.EventType.allCases.first(where: first.peak.contains) {
            let areas = all.filter { $0.peak.contains(phase) }.prefix(2).map(\.area)
            let verb = areas.count == 1 ? "tends" : "tend"
            parts.append("Your \(Self.areaList(Array(areas))) \(verb) to flare in the \(phase.rawValue) phase.")
        } else {
            parts.append("No area stands out in one phase yet.")
        }
        if let todayPhase, let cycleDay {
            parts.append("Today is \(todayPhase.rawValue) day \(cycleDay).")
        }
        return parts.joined(separator: " ")
    }

    /// Box-graph headline for one area, rules in design 9.3. nil when fewer than two phases have enough
    /// days or the lowest phase is 0%.
    func headline(area: SkinTag.Area, filter: KindFilter) -> (title: String, detail: String)? {
        guard let (high, low) = extremes(area: area), let p = high.percent, let q = low.percent, q >= 1 else { return nil }
        let detail = "\(p)% of \(high.phase.rawValue) days vs \(q)% of \(low.phase.rawValue) days"
        let ratio = Double(p) / Double(q)
        let name = area.rawValue
        let title: String
        if ratio >= 2 {
            title = "\(name) \(filter.verb) \(Int(ratio.rounded()))× more in \(high.phase.rawValue)"
        } else if ratio >= 1.5 {
            title = "\(name) \(filter.verb) more in \(high.phase.rawValue)"
        } else {
            title = "\(name) looks about the same across your phases."
        }
        return (title, detail)
    }

    /// "Chin 62% in luteal vs 10% in follicular. Mostly acne, red." nil unless two phases have enough days
    /// and the peak is above the lowest.
    func comparisonLine(area: SkinTag.Area) -> String? {
        guard let (high, low) = extremes(area: area), let p = high.percent, let q = low.percent, p > q else { return nil }
        var line = "\(area.rawValue) \(p)% in \(high.phase.rawValue) vs \(q)% in \(low.phase.rawValue)."
        let row = row(area: area)
        let words = [row.topKind?.rawValue, row.topColour?.rawValue].compactMap { $0?.lowercased() }
        if !words.isEmpty { line += " Mostly \(words.joined(separator: ", "))." }
        return line
    }

    /// Highest and lowest cells with a percentage (first phase wins ties), when at least two exist.
    private func extremes(area: SkinTag.Area) -> (high: PhaseCell, low: PhaseCell)? {
        let valued = cells(area: area).filter { $0.percent != nil }
        guard valued.count >= 2 else { return nil }
        var high = valued[0]
        for c in valued where c.percent! > high.percent! { high = c }
        let rest = valued.filter { $0.phase != high.phase }
        var low = rest[0]
        for c in rest where c.percent! < low.percent! { low = c }
        return (high, low)
    }

    /// Per phase: days with Sex or Intercourse (once per day) over days with any tag.
    func intimacyByPhase() -> [PhaseCell] {
        Event.EventType.allCases.map { phase in
            let days = tagsByDay.filter { phaseByDay[$0.key] == phase }
            let sex = days.values.filter { !$0.isDisjoint(with: Self.intimacyRaws) }.count
            return PhaseCell(phase: phase, loggedDays: days.count, flareDays: sex)
        }
    }

    /// Design 9.5. Any skin flare on skin-logged days with and without sex; nil unless both groups have
    /// `minimumDaysForComparison` days.
    func intimacySkinLine() -> String? {
        var with = (days: 0, flares: 0), without = (days: 0, flares: 0)
        for (day, tags) in skinByDay {
            let flared = tags.contains(where: \.isFlare)
            if tagsByDay[day]?.isDisjoint(with: Self.intimacyRaws) == false {
                with.days += 1; if flared { with.flares += 1 }
            } else {
                without.days += 1; if flared { without.flares += 1 }
            }
        }
        let m = Self.minimumDaysForComparison
        guard let p = Self.percent(with.flares, of: with.days, minimum: m),
              let q = Self.percent(without.flares, of: without.days, minimum: m) else { return nil }
        return "On days with sex logged, skin flared on \(p)% of logged days; on other logged days, \(q)%."
    }

    /// Distinct cycles with a logged day: the archived cycle block whose events include the day, else the
    /// live cycle when a live cycle event is on that day. Menopause blocks and events are not cycles.
    static func cyclesCovered(loggedDays: Set<Date>, events: [Event], archivedBlocks: [ArchivedDataBlock],
                              calendar: Calendar) -> Int {
        var blockByDay: [Date: UUID] = [:]
        for block in archivedBlocks where block.effectiveMode != .menopause {
            for event in block.groupedEvents.flatMap(\.events) {
                let key = calendar.startOfDay(for: event.date)
                if blockByDay[key] == nil { blockByDay[key] = block.id }
            }
        }
        let liveDays = Set(events.filter { $0.effectiveMode != .menopause }.map { calendar.startOfDay(for: $0.date) })
        var blocks = Set<UUID>()
        var live = false
        for day in loggedDays {
            let key = calendar.startOfDay(for: day)
            if let id = blockByDay[key] { blocks.insert(id) } else if liveDays.contains(key) { live = true }
        }
        return blocks.count + (live ? 1 : 0)
    }

    // MARK: Wording

    private var windowPhrase: String {
        switch window {
        case .days(let n): return "over the last \(n) days"
        case .all:         return "since you started logging"
        }
    }

    private static func areaList(_ areas: [SkinTag.Area]) -> String {
        let names = areas.map { $0.rawValue.lowercased() }
        switch names.count {
        case 0: return "skin"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}
