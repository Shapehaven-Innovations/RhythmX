//  TemplateInsightWriter.swift
//  The deterministic writer every device uses, and the fallback for the on-device writer. Warm, plain copy
//  per mode and phase: no emoji, no dashes as asides, no gendered or "goddess" wording, no medical advice.
//  Every fertility line ends with "Estimates only." and never suggests a day is safe.

import Foundation

struct TemplateInsightWriter: InsightWriting {
    static let estimateLine = "Estimates only."

    var isModelAvailable: Bool { false }

    /// Synchronous, which also satisfies the async `InsightWriting` requirement.
    func insights(for facts: InsightFacts) -> DailyInsights {
        let mood = Self.moodLine(for: facts)
        return DailyInsights(
            tiles: Self.tiles(for: facts),
            moodLine: mood,
            moodLineIsAI: false,
            notificationTitle: Self.notificationTitle(for: facts),
            notificationBody: mood
        )
    }

    // MARK: - Lines

    static func moodLine(for facts: InsightFacts) -> String {
        if facts.mode == .menopause { return "One day at a time. Your notes show what is changing." }
        switch facts.phase {
        case .menstrual?:  return "Rest and renew. Your body is working hard. Be kind to it."
        case .follicular?: return "Rising energy. A good time to start something new."
        case .ovulation?:  return "Full bloom. Energy and confidence often peak around now."
        case .luteal?:     return "Turn inward. Energy may soften before your period. Go gently."
        case nil:          return "Log a tag today and your rhythm will start to show."
        }
    }

    static func notificationTitle(for facts: InsightFacts) -> String {
        if facts.mode != .menopause, let day = facts.cycleDay { return "Cycle day \(day)" }
        return "Your daily note"
    }

    // MARK: - Tiles

    static func tiles(for facts: InsightFacts) -> [DailyInsightTile] {
        var tiles = [logPrompt(facts)]
        switch facts.mode {
        case .cycle, .planning:
            if let tile = cycleDay(facts) { tiles.append(tile) }
            if facts.mode == .cycle, let tile = possibleToday(facts) { tiles.append(tile) }
            if facts.mode == .planning, let tile = fertile(facts) { tiles.append(tile) }
            if let tile = pattern(facts) { tiles.append(tile) }
            if let tile = energy(facts) { tiles.append(tile) }
        case .menopause:
            if let tile = menopauseSymptoms(facts) { tiles.append(tile) }
            if let tile = sleep(facts) { tiles.append(tile) }
            if let tile = pattern(facts) { tiles.append(tile) }
        }
        return tiles
    }

    static func logPrompt(_ facts: InsightFacts) -> DailyInsightTile {
        let body: String
        switch facts.tagsLoggedToday {
        case 0:  body = "How is today? One tap is enough."
        case 1:  body = "1 tag logged today. Add another anytime."
        default: body = "\(facts.tagsLoggedToday) tags logged today. Add another anytime."
        }
        return DailyInsightTile(kind: .logPrompt, title: "Log a tag", body: body, symbols: ["plus"])
    }

    static func cycleDay(_ facts: InsightFacts) -> DailyInsightTile? {
        guard let day = facts.cycleDay else { return nil }
        var parts: [String] = []
        if let phase = facts.phase { parts.append("\(phase.rawValue.capitalized) phase.") }
        if let late = facts.periodLateDays {
            parts.append(late == 1 ? "Your period is 1 day later than estimated."
                                   : "Your period is \(late) days later than estimated.")
        } else if let until = facts.daysUntilPeriod {
            switch until {
            case 0:  parts.append("Your period may start today.")
            case 1:  parts.append("Your period may start tomorrow.")
            default: parts.append("Your period may start in about \(until) days.")
            }
        }
        return DailyInsightTile(kind: .cycleDay, title: "Cycle day \(day)", body: parts.joined(separator: " "),
                                symbols: ["moon"])
    }

    static func possibleToday(_ facts: InsightFacts) -> DailyInsightTile? {
        guard let phase = facts.phase else { return nil }
        let names = Array((TagFormLogic.phaseSymptomSuggestions[phase] ?? []).prefix(3))
        guard !names.isEmpty else { return nil }
        return DailyInsightTile(kind: .possibleToday, title: "Possible today",
                                body: "Common in this phase: \(listed(names)).",
                                symbols: names.map { TagFormLogic.suggestionCategory($0).symbolName })
    }

    static func fertile(_ facts: InsightFacts) -> DailyInsightTile? {
        guard let level = facts.fertileLevel else { return nil }
        let line: String
        switch level {
        case .low:    line = "Outside your estimated fertile window today."
        case .rising: line = "Your estimated fertile window may open in the next few days."
        case .high:   line = "Inside your estimated fertile window."
        case .peak:   line = "Today may be your most fertile day."
        }
        return DailyInsightTile(kind: .fertile, title: "Fertile window", body: "\(line) \(estimateLine)",
                                symbols: ["calendar.badge.plus"])
    }

    static func pattern(_ facts: InsightFacts) -> DailyInsightTile? {
        guard let pattern = facts.pattern else { return nil }
        return DailyInsightTile(kind: .pattern, title: "Your pattern", body: pattern.sentence, symbols: ["chart.bar"])
    }

    static func energy(_ facts: InsightFacts) -> DailyInsightTile? {
        guard let phase = facts.phase else { return nil }
        let body: String
        switch phase {
        case .menstrual:  body = "Lower today. Rest is part of the rhythm."
        case .follicular: body = "Building. A good day for plans and new things."
        case .ovulation:  body = "Often at its highest around now."
        case .luteal:     body = "Softer today. Keep plans light where you can."
        }
        return DailyInsightTile(kind: .energy, title: "Your energy", body: body, symbols: ["bolt"])
    }

    static func menopauseSymptoms(_ facts: InsightFacts) -> DailyInsightTile? {
        guard let thisWeek = facts.hotFlashesThisWeek else { return nil }
        let lastWeek = facts.hotFlashesLastWeek ?? 0
        let body = thisWeek == 0 && lastWeek == 0 ? "None logged this week." : "\(thisWeek) this week, \(lastWeek) last week."
        return DailyInsightTile(kind: .menopauseSymptoms, title: "Hot flashes", body: body, symbols: ["flame"])
    }

    static func sleep(_ facts: InsightFacts) -> DailyInsightTile? {
        guard let hours = facts.sleepAverageHours else { return nil }
        return DailyInsightTile(kind: .sleep, title: "Sleep",
                                body: "\(SleepInsights.hoursText(hours)) a night on average, from Apple Health.",
                                symbols: ["bed.double"])
    }

    /// "a", "a and b", "a, b and c".
    static func listed(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
}
