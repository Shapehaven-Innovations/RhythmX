//  DailyInsights.swift
//  The daily insights for one day: the tiles on Today, the one-line phase mood line and the daily
//  notification's text. Written by an `InsightWriting` from `InsightFacts`; no UI here.

import Foundation

struct DailyInsightTile: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case logPrompt
        case cycleDay
        case possibleToday
        case pattern
        case energy
        case fertile
        case sleep
        case menopauseSymptoms
    }

    /// One tile of each kind per day, so the kind is the id.
    let id: String
    let kind: Kind
    var title: String
    var body: String
    /// SF Symbol names, in display order.
    var symbols: [String]
    /// True when the body was written on this device by Apple Intelligence (the "Written on this device" label).
    var isAI: Bool

    init(kind: Kind, title: String, body: String, symbols: [String] = [], isAI: Bool = false) {
        self.id = kind.rawValue
        self.kind = kind
        self.title = title
        self.body = body
        self.symbols = symbols
        self.isAI = isAI
    }
}

struct DailyInsights: Codable, Equatable {
    var tiles: [DailyInsightTile]
    /// One line under the hero, in the tone of the phase.
    var moodLine: String
    var moodLineIsAI: Bool
    var notificationTitle: String
    var notificationBody: String

    /// True when any text was written on this device.
    var hasAIText: Bool { moodLineIsAI || tiles.contains { $0.isAI } }

    func tile(_ kind: DailyInsightTile.Kind) -> DailyInsightTile? { tiles.first { $0.kind == kind } }
}

/// Writes the daily insights for a day's facts. The template writer works everywhere; the on-device writer
/// uses Apple Intelligence when it is available and falls back to the template.
protocol InsightWriting {
    /// Whether the on-device model can write right now. Part of the cache key, so insights are rewritten
    /// when Apple Intelligence is turned on or off.
    var isModelAvailable: Bool { get }
    func insights(for facts: InsightFacts) async -> DailyInsights
}
