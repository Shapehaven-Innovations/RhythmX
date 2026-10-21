//  TagFormLogic.swift
//
//  Pure logic behind the Add Tag page (TagFormView): the stored "Category:Value" string, the selection tray,
//  search across every category, phase suggestions, the Recent row and the archive-based Smart Tags.
//  Nothing here reads or writes the stores; logging still goes through EventStore.logTag.

import Foundation

/// One tag the user can pick: a category and its value. `raw` is the stored form.
struct TagPick: Hashable, Identifiable {
    let category: TagCategory
    let value: String
    var raw: String { "\(category.rawValue):\(value)" }
    var id: String { raw }
    var isRepeatable: Bool { TagLibrary.isRepeatable(category, value) }
}

/// The tags picked on the Add Tag page, in the order they were picked. A normal tag is held once;
/// a repeatable tag (Menopause Hot Flashes and Night Sweats) can be held several times.
struct TagSelection: Equatable {
    struct Item: Equatable, Identifiable {
        let pick: TagPick
        var count: Int
        /// Light, medium or heavy, from the intensity rows; nil when picked without a level.
        var intensity: TagIntensity? = nil
        var id: String { pick.raw }
    }

    /// One stored tag string to log and the level to log it at.
    struct TagToLog: Equatable {
        let raw: String
        let intensity: TagIntensity?
    }

    private(set) var items: [Item] = []

    var isEmpty: Bool { items.isEmpty }
    var totalCount: Int { items.reduce(0) { $0 + $1.count } }

    func count(of pick: TagPick) -> Int { items.first { $0.pick == pick }?.count ?? 0 }
    func intensity(of pick: TagPick) -> TagIntensity? { items.first { $0.pick == pick }?.intensity }
    func contains(_ pick: TagPick) -> Bool { count(of: pick) > 0 }

    /// Adds the pick when it is not held yet; otherwise removes it.
    mutating func toggle(_ pick: TagPick) {
        if contains(pick) { remove(pick) } else { add(pick) }
    }

    /// Adds the pick once. Holding it already changes nothing.
    mutating func add(_ pick: TagPick) {
        guard !contains(pick) else { return }
        items.append(Item(pick: pick, count: 1))
    }

    /// One more of a repeatable tag (adds it when absent). A normal tag stays at one.
    mutating func increment(_ pick: TagPick) {
        guard let index = items.firstIndex(where: { $0.pick == pick }) else { add(pick); return }
        guard pick.isRepeatable else { return }
        items[index].count += 1
    }

    /// One fewer; the pick leaves the tray at zero.
    mutating func decrement(_ pick: TagPick) {
        guard let index = items.firstIndex(where: { $0.pick == pick }) else { return }
        items[index].count -= 1
        if items[index].count <= 0 { items.remove(at: index) }
    }

    mutating func remove(_ pick: TagPick) {
        items.removeAll { $0.pick == pick }
    }

    /// Sets the pick's level directly (VoiceOver adjust, the custom tag strength): a level holds the pick at
    /// it (adding it when absent), nil removes the pick.
    mutating func set(_ pick: TagPick, level: TagIntensity?) {
        guard let level else { remove(pick); return }
        if let index = items.firstIndex(where: { $0.pick == pick }) {
            items[index].intensity = level
        } else {
            items.append(Item(pick: pick, count: 1, intensity: level))
        }
    }

    /// A tap on one of the pick's level buttons (`TagFormLogic.tappedIntensity`): a new level holds the pick at
    /// that level (adding it when absent); the level it already holds clears the pick from the tray.
    mutating func tap(_ pick: TagPick, level: TagIntensity) {
        let current = intensity(of: pick)
        guard let next = TagFormLogic.tappedIntensity(current: current, tapped: level) else { remove(pick); return }
        if let index = items.firstIndex(where: { $0.pick == pick }) {
            items[index].intensity = next
        } else {
            items.append(Item(pick: pick, count: 1, intensity: next))
        }
    }

    /// Each stored tag string once per count, in pick order. Saving logs these one by one.
    var rawTagsToLog: [String] {
        items.flatMap { Array(repeating: $0.pick.raw, count: $0.count) }
    }

    /// `rawTagsToLog` with each tag's level, for `EventStore.logTag(_:on:mode:intensity:)`.
    var tagsToLog: [TagToLog] {
        items.flatMap { item in
            Array(repeating: TagToLog(raw: item.pick.raw, intensity: item.intensity), count: item.count)
        }
    }
}

/// Library tags of one category that match a search.
struct TagSearchGroup: Equatable {
    let category: TagCategory
    let values: [String]
}

/// A titled row of suggested tags.
struct TagSuggestionGroup: Equatable, Identifiable {
    let title: String
    let picks: [TagPick]
    var id: String { title }
}

enum TagFormLogic {

    // MARK: Intensity

    /// The three-step level control: tapping a level sets it; tapping the level already set clears it.
    static func tappedIntensity(current: TagIntensity?, tapped: TagIntensity) -> TagIntensity? {
        current == tapped ? nil : tapped
    }

    // MARK: Tag strings

    /// Trimmed, first letter upper-cased; blank becomes "unspecified". The format the form always saved.
    static func tagString(category: TagCategory, value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let capitalized = trimmed.isEmpty ? "unspecified" : (trimmed.prefix(1).uppercased() + trimmed.dropFirst())
        return "\(category.rawValue):\(capitalized)"
    }

    /// The text with every emoji character removed (pictographs, flags, skin tones, joined sequences and
    /// symbols shown as emoji). Digits, "#", "*", letters with accents and plain punctuation stay.
    /// Used on typed tags only; stored tags are never rewritten.
    static func removingEmoji(_ text: String) -> String {
        String(text.filter { character in
            !character.unicodeScalars.contains { scalar in
                let p = scalar.properties
                return p.isEmojiPresentation
                    || scalar.value == 0xFE0F || scalar.value == 0x200D || scalar.value == 0x20E3
                    || (p.isEmoji && scalar.value > 0x2000)
                    || (0x1F000...0x1FAFF).contains(scalar.value)
                    || (0xE0020...0xE007F).contains(scalar.value)
            }
        })
    }

    /// A typed custom tag for `category` (emoji dropped), or nil when the text is blank.
    static func customPick(category: TagCategory, text: String) -> TagPick? {
        let trimmed = removingEmoji(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return TagPick(category: category, value: trimmed.prefix(1).uppercased() + trimmed.dropFirst())
    }

    /// A stored or archived tag as a pick: the category prefix matched without case, an unknown prefix
    /// (or no colon at all) under Other. The rule the Smart Tag chips have always used.
    static func pick(fromRaw raw: String) -> TagPick {
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            return TagPick(category: .other, value: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let prefix = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return TagPick(category: category(named: prefix) ?? .other, value: value)
    }

    static func category(named name: String) -> TagCategory? {
        TagCategory.allCases.first { $0.rawValue.lowercased() == name.lowercased() }
    }

    // MARK: Categories and search

    /// The mode's categories first (`TagLibrary.categories(for:)`), then every other category.
    static func orderedCategories(for mode: TrackingMode) -> [TagCategory] {
        let first = TagLibrary.categories(for: mode)
        return first + TagCategory.allCases.filter { !first.contains($0) }
    }

    /// Library tags across `categories` whose value contains the query; a query that matches a category's
    /// name returns all of that category's tags. Case and accents are ignored. A blank query finds nothing.
    static func search(_ query: String, categories: [TagCategory]) -> [TagSearchGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        func matches(_ text: String) -> Bool {
            text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return categories.compactMap { category in
            let values = TagLibrary.tags[category] ?? []
            let hits = matches(category.rawValue) ? values : values.filter(matches)
            return hits.isEmpty ? nil : TagSearchGroup(category: category, values: hits)
        }
    }

    // MARK: Suggestions

    /// The quick picks per cycle phase the form has always offered.
    static let phaseSymptomSuggestions: [Event.EventType: [String]] = [
        .menstrual:  ["Cramps", "Bloating", "Fatigue", "Headache", "Irritable"],
        .follicular: ["Increased Energy", "Clearer Thinking", "Higher Libido"],
        .ovulation:  ["Mittelschmerz", "Bloating", "Mild Cramping"],
        .luteal:     ["Mood Swings", "Breast Tenderness", "Food Cravings", "PMS"]
    ]

    /// Suggestions go under Symptom unless they are a known mood tag (e.g. "Mood Swings").
    static func suggestionCategory(_ suggestion: String) -> TagCategory {
        (TagLibrary.tags[.mood] ?? []).contains(suggestion) ? .mood : .symptom
    }

    /// The "Suggested for this phase" rows: the phase picks; cervical mucus in the follicular and ovulation
    /// phases; ovulation test results in those phases in Planning mode. With no phase (Menopause, or a day
    /// outside the cycle) Menopause mode gets its most common tags and other modes get nothing.
    static func suggestionGroups(phase: Event.EventType?, mode: TrackingMode) -> [TagSuggestionGroup] {
        guard let phase else {
            guard mode == .menopause else { return [] }
            let common = (TagLibrary.tags[.menopause] ?? []).prefix(4).map { TagPick(category: .menopause, value: $0) }
            return [TagSuggestionGroup(title: "Common in menopause", picks: Array(common))]
        }
        var groups: [TagSuggestionGroup] = []
        let picks = (phaseSymptomSuggestions[phase] ?? []).map { TagPick(category: suggestionCategory($0), value: $0) }
        if !picks.isEmpty {
            groups.append(TagSuggestionGroup(title: "Common in the \(phase.rawValue) phase", picks: picks))
        }
        if phase == .follicular || phase == .ovulation {
            if mode == .planning {
                let tests = (TagLibrary.tags[.planning] ?? []).filter { $0.hasPrefix("Ovulation Test") }
                groups.append(TagSuggestionGroup(title: "Ovulation test result",
                                                 picks: tests.map { TagPick(category: .planning, value: $0) }))
            }
            groups.append(TagSuggestionGroup(title: "Cervical mucus",
                                             picks: (TagLibrary.tags[.cervicalMucus] ?? []).map { TagPick(category: .cervicalMucus, value: $0) }))
        }
        return groups
    }

    // MARK: Recent

    /// The tags logged most recently in the current mode (Menopause events for Menopause; Cycle and Planning
    /// share the cycle events), over the last `windowDays` and never from a future day. Latest day first,
    /// then the most often logged, then by name. Typed temperature readings are left out.
    static func recentTags(events: [Event], mode: TrackingMode, now: Date, limit: Int = 8,
                           windowDays: Int = 90, calendar: Calendar = .current) -> [TagPick] {
        let today = calendar.startOfDay(for: now)
        let earliest = calendar.date(byAdding: .day, value: -windowDays, to: today) ?? .distantPast
        var latest: [String: Date] = [:]
        var counts: [String: Int] = [:]
        var picks: [String: TagPick] = [:]
        for event in events where (mode == .menopause) == (event.effectiveMode == .menopause) {
            let day = calendar.startOfDay(for: event.date)
            guard day <= today, day >= earliest else { continue }
            for raw in TagParser.split(event.tags) {
                let pick = pick(fromRaw: raw)
                guard !pick.value.isEmpty else { continue }
                if pick.category == .basalTemp, Double(pick.value) != nil { continue }
                picks[pick.raw] = pick
                counts[pick.raw, default: 0] += 1
                latest[pick.raw] = max(latest[pick.raw] ?? .distantPast, day)
            }
        }
        return picks.keys
            .sorted { a, b in
                if latest[a] != latest[b] { return latest[a]! > latest[b]! }
                if counts[a] != counts[b] { return counts[a]! > counts[b]! }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            .prefix(limit)
            .compactMap { picks[$0] }
    }

    // MARK: Smart Tags (archive, cycle blocks only)

    /// Archived tags from the same phase of past cycles, most frequent first (ties by name).
    /// Callers pass `ArchivedDataStore.cycleBlocks`. No phase means no history.
    static func historyTags(phase: Event.EventType?, blocks: [ArchivedDataBlock]) -> [String] {
        guard let phase else { return [] }
        var frequency: [String: Int] = [:]
        for block in blocks {
            for archivedPhase in block.groupedEvents where archivedPhase.eventType == phase {
                for archivedEvent in archivedPhase.events {
                    for t in TagParser.split(archivedEvent.tags) { frequency[t, default: 0] += 1 }
                }
            }
        }
        return frequency
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
    }

    /// The Smart Tags list: archive history for the phase, then the chosen category's library tags not
    /// already in it, eight at most.
    static func smartTags(phase: Event.EventType?, blocks: [ArchivedDataBlock], category: TagCategory) -> [String] {
        let ranked = historyTags(phase: phase, blocks: blocks)
        let existing = Set(ranked)
        let additional = (TagLibrary.tags[category] ?? [])
            .filter { !existing.contains("\(category.rawValue):\($0)") && !existing.contains($0) }
            .map { "\(category.rawValue):\($0)" }
        return Array((ranked + additional).prefix(8))
    }

    /// The category most used in this phase of past cycles: where the form opens in Cycle mode.
    static func topCategory(phase: Event.EventType?, blocks: [ArchivedDataBlock]) -> TagCategory? {
        guard let phase else { return nil }
        var categoryFreq: [TagCategory: Int] = [:]
        for block in blocks {
            for archivedPhase in block.groupedEvents where archivedPhase.eventType == phase {
                for archivedEvent in archivedPhase.events {
                    for tag in TagParser.split(archivedEvent.tags) {
                        let parts = tag.split(separator: ":", maxSplits: 1)
                        guard parts.count == 2,
                              let cat = category(named: parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
                        else { continue }
                        categoryFreq[cat, default: 0] += 1
                    }
                }
            }
        }
        return categoryFreq.max { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }?.key
    }
}

// MARK: - Category symbols

extension TagCategory {
    /// SF Symbol for the category strip and section headers.
    var symbolName: String {
        switch self {
        case .dietary:       return "fork.knife"
        case .exercise:      return "figure.walk"
        case .medication:    return "pills"
        case .mood:          return "face.smiling"
        case .symptom:       return "waveform.path.ecg"
        case .cervicalMucus: return "drop"
        case .basalTemp:     return "thermometer.medium"
        case .other:         return "ellipsis"
        case .planning:      return "testtube.2"
        case .menopause:     return "flame"
        }
    }
}

// MARK: - Add Tags sheet (moon intensity rows)

/// How a category's body is drawn in the Add Tags sheet.
enum TagBodyKind: Equatable {
    /// A label and the three-step moon control per tag (Symptom).
    case intensityRows
    /// The round glyph grid, one tap each (Mood).
    case moodGrid
    /// The ovulation test strip picker plus Intercourse and Fertility Supplement toggles.
    case planning
    /// The temperature entry with the Apple Health suggestion.
    case basalTemp
    /// Counters for the repeatable tags, moon rows for the rest.
    case menopause
    /// One-tap chips (Dietary, Exercise, Medication, Cervical Mucus, Other).
    case chips
}

/// One tag in a category body and the control it gets.
struct TagRow: Equatable, Identifiable {
    enum Kind: Equatable { case intensity, counter, ovulationTest, toggle, chip }
    let pick: TagPick
    let kind: Kind
    var id: String { pick.raw }
}

/// What a search found: library tags by category, or (when nothing matches) the typed text as a custom tag.
struct TagSearchOutcome: Equatable {
    let groups: [TagSearchGroup]
    let customValue: String?
}

extension TagFormLogic {

    // MARK: Bodies and rows

    static func bodyKind(for category: TagCategory) -> TagBodyKind {
        switch category {
        case .symptom:   return .intensityRows
        case .mood:      return .moodGrid
        case .planning:  return .planning
        case .basalTemp: return .basalTemp
        case .menopause: return .menopause
        case .dietary, .exercise, .medication, .cervicalMucus, .other: return .chips
        }
    }

    /// Symptom tags and the Menopause tags that are once a day take a strength (light, medium, heavy).
    static func supportsIntensity(_ pick: TagPick) -> Bool {
        switch pick.category {
        case .symptom:   return true
        case .menopause: return !pick.isRepeatable
        default:         return false
        }
    }

    static func isOvulationTest(_ pick: TagPick) -> Bool {
        pick.category == .planning && pick.value.hasPrefix("Ovulation Test")
    }

    /// "Ovulation Test Peak" -> "Peak", for the strip picker.
    static func ovulationTestShortName(_ value: String) -> String {
        value.hasPrefix("Ovulation Test ") ? String(value.dropFirst("Ovulation Test ".count)) : value
    }

    /// The category's library tags, then any custom tag of that category already picked, each with its control.
    static func rows(for category: TagCategory, selection: TagSelection) -> [TagRow] {
        var library = TagLibrary.tags[category] ?? []
        if category == .mood {
            library.sort { (moodGridOrder.firstIndex(of: $0) ?? .max) < (moodGridOrder.firstIndex(of: $1) ?? .max) }
        }
        let custom = selection.items.map(\.pick).filter { $0.category == category && !library.contains($0.value) }
        let picks = library.map { TagPick(category: category, value: $0) } + custom
        return picks.map { TagRow(pick: $0, kind: rowKind($0)) }
    }

    /// The mood grid reads from bright to heavy, as in the design.
    static let moodGridOrder = ["Happy", "Calm", "Focused", "Motivated", "Irritable", "Anxious",
                                "Low Energy", "Emotional", "Mood Swings"]

    private static func rowKind(_ pick: TagPick) -> TagRow.Kind {
        if pick.isRepeatable { return .counter }
        if supportsIntensity(pick) { return .intensity }
        if pick.category == .planning { return isOvulationTest(pick) ? .ovulationTest : .toggle }
        return .chip
    }

    /// Ovulation test results are one per day: a new result replaces the one picked; the same result clears it.
    static func chooseOvulationTest(_ pick: TagPick, in selection: inout TagSelection) {
        if selection.contains(pick) { selection.remove(pick); return }
        for item in selection.items where isOvulationTest(item.pick) { selection.remove(item.pick) }
        selection.add(pick)
    }

    // MARK: Search

    /// Every category at once, the mode's first. With no match the text (emoji dropped) is offered as a custom tag.
    static func searchOutcome(_ query: String, mode: TrackingMode) -> TagSearchOutcome {
        let groups = search(query, categories: orderedCategories(for: mode))
        let custom = groups.isEmpty ? customPick(category: .other, text: query)?.value : nil
        return TagSearchOutcome(groups: groups, customValue: custom)
    }

    static func customTagTitle(_ value: String) -> String { "Add \u{201C}\(value)\u{201D} as a custom tag" }

    /// Where a custom tag can go: the mode's own category (Planning, Menopause), then Symptom, Mood, Medication, Other.
    static func customCategories(for mode: TrackingMode) -> [TagCategory] {
        let common: [TagCategory] = [.symptom, .mood, .medication, .other]
        return mode == .cycle ? common : [mode.mainCategory] + common
    }

    // MARK: Tray

    /// The picks in the mode's category order, then library order within a category (custom tags last), then pick order.
    static func trayItems(_ selection: TagSelection, mode: TrackingMode) -> [TagSelection.Item] {
        let order = orderedCategories(for: mode)
        func key(_ item: TagSelection.Item) -> (Int, Int) {
            let categoryIndex = order.firstIndex(of: item.pick.category) ?? order.count
            let libraryIndex = (TagLibrary.tags[item.pick.category] ?? []).firstIndex(of: item.pick.value) ?? Int.max
            return (categoryIndex, libraryIndex)
        }
        return selection.items.enumerated()
            .sorted { a, b in
                let ka = key(a.element), kb = key(b.element)
                if ka != kb { return ka < kb }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    static func addButtonTitle(count: Int) -> String {
        switch count {
        case 0:  return "Add Tags"
        case 1:  return "Add 1 Tag"
        default: return "Add \(count) Tags"
        }
    }

    static func trayAccessibilityLabel(_ item: TagSelection.Item) -> String {
        if item.pick.isRepeatable { return item.count == 1 ? "\(item.pick.value), once" : "\(item.pick.value), \(item.count) times" }
        if let level = item.intensity { return "\(item.pick.value), \(level.title)" }
        return item.pick.value
    }

    // MARK: Intensity (moon control)

    /// The VoiceOver value of the moon control.
    static func intensityValue(_ level: TagIntensity?) -> String { level?.title ?? "Off" }

    /// VoiceOver adjust: up steps Off, Light, Medium, Heavy; down steps back to Off.
    static func adjusted(_ level: TagIntensity?, up: Bool) -> TagIntensity? {
        let raw = (level?.rawValue ?? 0) + (up ? 1 : -1)
        return TagIntensity(rawValue: min(max(raw, 0), 3))
    }

    // MARK: Suggested row

    /// "For your <phase> phase": her own tags from this phase of past cycles first, then the phase picks
    /// (`suggestionGroups`), each once. Menopause gets "Common in menopause"; a day with no phase in the
    /// other modes gets nothing.
    static func suggestedRow(phase: Event.EventType?, mode: TrackingMode, history: [TagPick], limit: Int = 12) -> TagSuggestionGroup? {
        let groups = suggestionGroups(phase: phase, mode: mode)
        var seen = Set<TagPick>()
        let picks = (history + groups.flatMap(\.picks)).filter { seen.insert($0).inserted }.prefix(limit)
        guard !picks.isEmpty else { return nil }
        let title = phase.map { "For your \($0.rawValue) phase" } ?? (groups.first?.title ?? "Suggested for you")
        return TagSuggestionGroup(title: title, picks: Array(picks))
    }

    // MARK: Header and day

    /// The cycle day of `date`: days since the period start on or before it, counted from 1. Nil when no cycle
    /// event is on that day (Menopause carriers do not count).
    static func cycleDay(on date: Date, events: [Event], calendar: Calendar = .current) -> Int? {
        let cycle = events.filter { $0.effectiveMode != .menopause }
        let target = calendar.startOfDay(for: date)
        guard cycle.contains(where: { calendar.isDate($0.date, inSameDayAs: target) }) else { return nil }
        let menstrualDays = Set(cycle.filter { $0.eventType == .menstrual }.map { calendar.startOfDay(for: $0.date) })
        let starts = menstrualDays.filter { day in
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return true }
            return !menstrualDays.contains(previous)
        }
        let start = starts.filter { $0 <= target }.max()
            ?? cycle.map { calendar.startOfDay(for: $0.date) }.filter { $0 <= target }.min()
        guard let start else { return nil }
        return (calendar.dateComponents([.day], from: start, to: target).day ?? 0) + 1
    }

    /// "Tue, Oct 20 · Day 26 · Luteal"; Planning names the mode in place of the phase; Menopause shows the mode.
    static func headerSubtitle(dateText: String, cycleDay: Int?, phase: Event.EventType?, mode: TrackingMode) -> String {
        var parts = [dateText]
        if mode == .menopause {
            parts.append(mode.title)
        } else if let cycleDay {
            parts.append("Day \(cycleDay)")
            if mode == .planning { parts.append(mode.title) } else if let phase { parts.append(phase.rawValue.capitalized) }
        } else {
            parts.append("No cycle day")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Cycle and Planning tags need a cycle day to hold them (`EventStore.eventForLogging`); Menopause makes one.
    static func canHoldTags(on date: Date, mode: TrackingMode, events: [Event], calendar: Calendar = .current) -> Bool {
        mode == .menopause || events.contains {
            calendar.isDate($0.date, inSameDayAs: date) && $0.effectiveMode != .menopause
        }
    }

    /// Picks that would stop the save with the duplicate alert: a one-per-day tag already on the day, unless it
    /// carries a new level (`EventStore.logTag` then changes the stored level).
    static func blockedDuplicates(_ items: [TagSelection.Item], isDuplicate: (String) -> Bool,
                                  storedLevel: (String) -> TagIntensity?) -> [TagSelection.Item] {
        items.filter { item in
            guard isDuplicate(item.pick.raw) else { return false }
            // A different level, or no level where one is stored (turning it off), is a change.
            return storedLevel(item.pick.raw) == item.intensity
        }
    }

    /// Under a Menopause counter: how many are already logged that day.
    static func loggedCountText(_ count: Int) -> String {
        switch count {
        case 0:  return "None logged yet this day"
        case 1:  return "Logged once this day"
        default: return "Logged \(count) times this day"
        }
    }
}

// MARK: - Tag glyphs

/// SF Symbols for the round mood buttons and the quick log choices. Tags without their own glyph use
/// their category's symbol.
enum TagGlyph {
    static let symbols: [String: String] = [
        "Mood:Happy": "sun.max",
        "Mood:Calm": "water.waves",
        "Mood:Focused": "scope",
        "Mood:Motivated": "arrow.up.right",
        "Mood:Irritable": "bolt",
        "Mood:Anxious": "tornado",
        "Mood:Low Energy": "battery.25percent",
        "Mood:Emotional": "drop",
        "Mood:Mood Swings": "waveform.path",
        "Symptom:Cramps": "bolt.heart",
        "Symptom:Bloating": "balloon",
        "Symptom:Headache": "brain.head.profile",
        "Symptom:Fatigue": "zzz",
        "Symptom:Back Pain": "figure.stand",
        "Symptom:Nausea": "face.dashed",
        "Symptom:Breast Tenderness": "heart",
        "Symptom:Spotting": "drop.fill",
        "Symptom:Food Cravings": "birthday.cake",
        "Symptom:PMS": "cloud.drizzle",
        "Symptom:Increased Energy": "bolt.fill",
        "Symptom:Clearer Thinking": "lightbulb",
        "Symptom:Higher Libido": "heart.fill",
        "Dietary:Sweet Craving": "birthday.cake",
        "Dietary:Chocolate Craving": "birthday.cake",
        "Planning:Intercourse": "heart.fill",
        "Planning:Fertility Supplement": "pills.fill",
        "Cervical Mucus:Egg White": "drop.fill",
        "Menopause:Hot Flashes": "flame",
        "Menopause:Night Sweats": "moon.zzz",
        "Menopause:Poor Sleep": "bed.double",
        "Menopause:Brain Fog": "cloud.fog",
        "Menopause:Joint Pain": "figure.walk",
        "Menopause:Heart Palpitations": "heart.text.square",
    ]

    static func symbol(for pick: TagPick) -> String {
        if TagFormLogic.isOvulationTest(pick) { return "testtube.2" }
        return symbols[pick.raw] ?? pick.category.symbolName
    }
}
