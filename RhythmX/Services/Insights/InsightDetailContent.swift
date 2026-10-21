//  InsightDetailContent.swift
//  What the daily insight pull-up shows for a tile, per mode: the eyebrow, which chart ("Where you are" curve
//  in Cycle and Planning, the fertile band in Planning, an 8-week trend in Menopause), the suggested tag chips
//  and their main button, which share card matches, and which footers apply. Pure.

import Foundation

struct InsightDetailContent: Equatable {
    enum Chart: Equatable {
        /// Typical hormone curves with the marker at `day`; the fertile band only in Planning.
        case hormones(day: Int, length: Int, fertileBand: ClosedRange<Double>?)
        /// Menopause: hot flashes in each of the last 8 weeks, oldest first.
        case menopauseTrend(weeks: [Int])
        case none
    }

    static let footer = "It can be wrong. Tracking tool, not medical advice."
    static let fertilityFooter = "Predictions are estimates and are not birth control."
    static let curveCaption = "Typical pattern, estimates only"
    static let curveTitle = "Where you are"
    static let trendTitle = "Hot flashes, last 8 weeks"
    static let trendWeeks = 8
    static let maxChips = 3

    let eyebrow: String
    let title: String
    let chart: Chart
    let chips: [TagPick]
    let showsFertilityLine: Bool
    let shareKind: ShareCard.Kind?

    var primaryChip: TagPick? { chips.first }
    /// "Log Sweet Craving", or "Log a Tag" (opens Add Tag) when there is nothing to suggest.
    var primaryTitle: String { primaryChip.map { "Log \($0.value)" } ?? "Log a Tag" }

    /// - Parameters:
    ///   - choices: suggested tags, best first (`QuickLogCardLogic.choices`).
    ///   - patternPick: the tag of the day's top pattern; it leads on the pattern tile.
    ///   - shareKinds: the cards Share offers today (`ShareCardModel.cards`).
    static func make(tile: DailyInsightTile, mode: TrackingMode, phase: Event.EventType?, cycleDay: Int?,
                     cycleLength: Int, hotFlashWeeks: [Int], choices: [TagPick], patternPick: TagPick?,
                     shareKinds: Set<ShareCard.Kind>) -> InsightDetailContent {
        let chart: Chart
        let eyebrow: String
        if mode == .menopause {
            let recent = Array(hotFlashWeeks.suffix(trendWeeks))
            chart = .menopauseTrend(weeks: Array(repeating: 0, count: trendWeeks - recent.count) + recent)
            eyebrow = "Menopause · This week"
        } else if let day = cycleDay {
            let length = HormoneCurve.clampedLength(cycleLength)
            let band = mode == .planning || tile.kind == .fertile ? HormoneCurve.fertileBand(length: length) : nil
            chart = .hormones(day: min(day, length), length: length, fertileBand: band)
            eyebrow = phase.map { "Day \(day) · \($0.rawValue.capitalized)" } ?? "Day \(day)"
        } else {
            chart = .none
            eyebrow = mode.title
        }

        var chips: [TagPick] = []
        for pick in ([tile.kind == .pattern ? patternPick : nil].compactMap { $0 } + choices)
            where chips.count < maxChips && !chips.contains(pick) {
            chips.append(pick)
        }

        let fertility: Bool = {
            if tile.kind == .fertile { return true }
            if case .hormones(_, _, let band) = chart { return band != nil }
            return false
        }()

        return InsightDetailContent(eyebrow: eyebrow, title: tile.title, chart: chart, chips: chips,
                                    showsFertilityLine: fertility,
                                    shareKind: shareKind(for: tile.kind, available: shareKinds))
    }

    /// The card that says the same as the tile; the combined card when that one is not offered today.
    static func shareKind(for kind: DailyInsightTile.Kind, available: Set<ShareCard.Kind>) -> ShareCard.Kind? {
        let preferred: ShareCard.Kind?
        switch kind {
        case .cycleDay:          preferred = .cycleDay
        case .possibleToday:     preferred = .possibleToday
        case .energy:            preferred = .phase
        case .fertile:           preferred = .bestChances
        case .menopauseSymptoms: preferred = .hotFlashes
        case .pattern, .sleep, .logPrompt: preferred = .combined
        }
        if let preferred, available.contains(preferred) { return preferred }
        return available.contains(.combined) ? .combined : nil
    }
}
