//  QuickLogCardLogic.swift
//
//  Pure logic behind the quick log card a Daily insights tap opens (QuickLogCardView): which four round
//  choices it offers, the question it asks, the selection with "None of these", and the one-tap log.
//  Logging goes through EventStore.logTag, so the stored strings and the duplicate rules are unchanged.

import Foundation

/// What is picked on the quick log card. "None of these" and the tags exclude each other.
struct QuickLogSelection: Equatable {
    private(set) var picks: [TagPick] = []
    private(set) var noneChosen = false

    func contains(_ pick: TagPick) -> Bool { picks.contains(pick) }

    /// Picks or unpicks a tag and clears "None of these". Ovulation test results replace each other.
    mutating func toggle(_ pick: TagPick) {
        noneChosen = false
        if let index = picks.firstIndex(of: pick) { picks.remove(at: index); return }
        if TagFormLogic.isOvulationTest(pick) { picks.removeAll(where: TagFormLogic.isOvulationTest) }
        picks.append(pick)
    }

    /// "None of these": clears the picks (a second tap clears it again).
    mutating func chooseNone() {
        noneChosen.toggle()
        if noneChosen { picks = [] }
    }

    var canApply: Bool { noneChosen || !picks.isEmpty }

    var buttonTitle: String {
        if noneChosen { return "Done" }
        return picks.isEmpty ? "Log" : "Log \(picks.count)"
    }

    /// Each pick once, at medium where a strength applies (`TagFormLogic.supportsIntensity`).
    var tagsToLog: [TagSelection.TagToLog] {
        guard !noneChosen else { return [] }
        return picks.map { TagSelection.TagToLog(raw: $0.raw, intensity: TagFormLogic.supportsIntensity($0) ? .medium : nil) }
    }
}

enum QuickLogCardLogic {

    static let eyebrow = "From your daily insight"

    static func question(mode: TrackingMode, phase: Event.EventType?) -> String {
        guard mode != .menopause, let phase else { return "Have you noticed anything today?" }
        return "Anything from your \(phase.rawValue) phase today?"
    }

    /// Up to `limit` tags for the round choices: her own tags from this phase of past cycles (`history`, the
    /// archive's Smart Tags), then what she logged most on days of this phase, then what she logged most in the
    /// mode over the last 90 days, then the phase suggestions, then the mode's main category. Only the mode's
    /// categories, no temperatures, and no one-per-day tag already logged today.
    static func choices(mode: TrackingMode, phase: Event.EventType?, events: [Event], history: [String],
                        today: Date, limit: Int = 4, calendar: Calendar = .current) -> [TagPick] {
        let day = calendar.startOfDay(for: today)
        let earliest = calendar.date(byAdding: .day, value: -90, to: day) ?? .distantPast
        let modeEvents = events.filter {
            (mode == .menopause) == ($0.effectiveMode == .menopause)
                && calendar.startOfDay(for: $0.date) <= day && calendar.startOfDay(for: $0.date) >= earliest
        }
        let loggedToday = Set(events.filter { calendar.isDate($0.date, inSameDayAs: day) }.flatMap { TagParser.split($0.tags) })

        func ranked(_ source: [Event]) -> [TagPick] {
            var counts: [String: Int] = [:]
            for event in source { for raw in TagParser.split(event.tags) { counts[raw, default: 0] += 1 } }
            return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map { TagFormLogic.pick(fromRaw: $0.key) }
        }
        let samePhase = (mode == .menopause || phase == nil) ? [] : ranked(modeEvents.filter { $0.eventType == phase })
        let suggestions = TagFormLogic.suggestionGroups(phase: mode == .menopause ? nil : phase, mode: mode).flatMap(\.picks)
        let fallback = (TagLibrary.tags[mode.mainCategory] ?? []).map { TagPick(category: mode.mainCategory, value: $0) }
        let candidates = history.map(TagFormLogic.pick(fromRaw:)) + samePhase + ranked(modeEvents) + suggestions + fallback

        let allowed = Set(TagLibrary.categories(for: mode)).subtracting([.basalTemp])
        var seen = Set<TagPick>()
        var result: [TagPick] = []
        for pick in candidates where result.count < limit {
            guard allowed.contains(pick.category), !pick.value.isEmpty, seen.insert(pick).inserted else { continue }
            if !pick.isRepeatable && loggedToday.contains(pick.raw) { continue }
            result.append(pick)
        }
        return result
    }

    static func loggedTitle(cycleDay: Int?) -> String {
        cycleDay.map { "Logged for day \($0)" } ?? "Logged for today"
    }

    static func loggedDetail(_ picks: [TagPick]) -> String {
        "\(picks.map(\.value).joined(separator: ", ")). See you tomorrow."
    }

    /// Logs the picks to `date` through `EventStore.logTag`, one call each, and returns the ones written.
    /// A one-per-day tag already logged at that level is skipped, as the store has always done.
    @MainActor
    static func log(_ selection: QuickLogSelection, store: EventStore, on date: Date, mode: TrackingMode) -> [TagPick] {
        selection.tagsToLog.compactMap { tag in
            store.logTag(tag.raw, on: date, mode: mode, intensity: tag.intensity) ? TagFormLogic.pick(fromRaw: tag.raw) : nil
        }
    }
}
