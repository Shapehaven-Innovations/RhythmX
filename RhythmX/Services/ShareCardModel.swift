//  ShareCardModel.swift
//  The insight cards Share offers and the text on each. Pure: built only from the day's `DailyInsights`
//  tiles and `InsightFacts` counts and labels, so a card never carries tags, notes or dates. Fertility cards
//  (Planning's best chances) always carry "Estimates only." and the birth control line. Menopause never gets a
//  cycle, phase or fertility card. The view (`ShareCardView`) only lays this out.

import CoreGraphics
import Foundation

/// Everything a card may be built from.
struct ShareCardInput {
    var mode: TrackingMode
    var insights: DailyInsights
    var facts: InsightFacts
    /// From the same snapshot the Today tile uses; counts only.
    var fertileToday: Bool
    var fertileStartsIn: Int?
    /// `AppSettings.sharerName`; blank shows no name.
    var sharerName: String
}

struct ShareCard: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case cycleDay, possibleToday, phase, bestChances, hotFlashes, combined, minimal
    }

    /// Moon: the theme accent with the moon. Aura: the accent under a phase glow. Minimal: the card colour.
    enum Style: Equatable { case moon, aura, minimal }

    struct Item: Equatable {
        let symbol: String
        let label: String
    }

    /// One line of the combined card: a bold lead and the rest ("Period" "in about 3 days").
    struct Fact: Equatable {
        let lead: String
        let rest: String
    }

    let kind: Kind
    var id: String { kind.rawValue }
    let style: Style
    /// The row in the Include list.
    let pickerTitle: String
    let pickerSummary: String

    let eyebrow: String
    /// The large text: a number ("26"), "Now", or a short title ("Turn inward").
    let big: String?
    /// Next to a large number: "days", or the phase on the combined card.
    var bigSide: String? = nil
    var bigSideDetail: String? = nil
    var subtitle: String? = nil
    var detail: String? = nil
    var items: [Item] = []
    var facts: [Fact] = []
    var estimateLine: String? = nil
    var disclaimer: String? = nil
    /// The current phase, for the moon and the ring; nil in Menopause.
    var phase: Event.EventType? = nil
    var cycleDay: Int? = nil
    let footer: String
    let sharerLine: String?

    /// True when `big` is a number, drawn very large.
    var bigIsNumber: Bool { big.map { Int($0) != nil } ?? false }

    var fileName: String {
        let slug: String
        switch kind {
        case .cycleDay:      slug = "cycle-day"
        case .possibleToday: slug = "possible-today"
        case .phase:         slug = "phase"
        case .bestChances:   slug = "best-chances"
        case .hotFlashes:    slug = "hot-flashes"
        case .combined:      slug = "my-day"
        case .minimal:       slug = "my-day-minimal"
        }
        return "RhythmX-\(slug).png"
    }

    /// The whole card read as sentences, for VoiceOver and as the image's description.
    var accessibilityDescription: String {
        func sentence(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.hasSuffix(".") ? t : t + "."
        }
        var parts = ["\(pickerTitle) card."]
        if let big {
            let side = [bigSide, bigSideDetail].compactMap { $0 }
            if bigIsNumber || big == "Now" {
                parts.append(sentence(([eyebrow, big] + side.prefix(1)).joined(separator: " ")))
                side.dropFirst().forEach { parts.append(sentence($0)) }
            } else {
                parts.append(sentence(eyebrow))
                parts.append(sentence(big))
                side.forEach { parts.append(sentence($0)) }
            }
        } else {
            parts.append(sentence(eyebrow))
        }
        if !items.isEmpty { parts.append(sentence(items.map(\.label).joined(separator: ", "))) }
        [subtitle, detail].compactMap { $0 }.forEach { parts.append(sentence($0)) }
        facts.forEach { parts.append(sentence("\($0.lead) \($0.rest)")) }
        [estimateLine, disclaimer, sharerLine].compactMap { $0 }.forEach { parts.append(sentence($0)) }
        parts.append(sentence(footer))
        return parts.joined(separator: " ")
    }
}

enum ShareCardModel {
    /// The card in points; rendered at 3x to 1080 by 1350 pixels (4:5, what Messages and Instagram show whole).
    static let pointSize = CGSize(width: 360, height: 450)
    static let renderScale: CGFloat = 3
    static let pixelSize = CGSize(width: 1080, height: 1350)
    static let footer = "Shared from RhythmX"
    static let maxNameLength = 30

    static func cards(for input: ShareCardInput) -> [ShareCard] {
        let sharer = sharerLine(input.sharerName)
        switch input.mode {
        case .menopause:
            return menopauseCards(input, sharer: sharer)
        case .cycle, .planning:
            return cycleCards(input, sharer: sharer)
        }
    }

    /// The single cards start selected; the combined and minimal ones are offered as alternatives.
    static func defaultSelection(_ cards: [ShareCard]) -> Set<ShareCard.Kind> {
        Set(cards.map(\.kind).filter { $0 != .combined && $0 != .minimal })
    }

    static func shareButtonTitle(count: Int) -> String {
        switch count {
        case 0:  return "Share"
        case 1:  return "Share Card"
        default: return "Share \(count) Cards"
        }
    }

    static func sharerLine(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "From \(String(trimmed.prefix(maxNameLength)))"
    }

    // MARK: - Cycle and Planning

    private static func cycleCards(_ input: ShareCardInput, sharer: String?) -> [ShareCard] {
        let facts = input.facts
        guard let day = facts.cycleDay, input.insights.tile(.cycleDay) != nil else { return [] }
        let phase = facts.phase
        let period = periodLine(facts)
        let headline = phase.map(phaseHeadline)
        var cards: [ShareCard] = []

        cards.append(ShareCard(
            kind: .cycleDay, style: .moon, pickerTitle: "Cycle day",
            pickerSummary: (["Day \(day)"] + [period.map { $0.lowercasedFirst }].compactMap { $0 }).joined(separator: ", "),
            eyebrow: "Cycle day", big: "\(day)",
            subtitle: phase.map { "\($0.rawValue.capitalized) phase" },
            detail: period, phase: phase, cycleDay: day, footer: footer, sharerLine: sharer))

        let symptoms = input.mode == .cycle ? possibleToday(input) : []
        if !symptoms.isEmpty {
            cards.append(ShareCard(
                kind: .possibleToday, style: .moon, pickerTitle: "Possible symptoms",
                pickerSummary: listed(symptoms.map(\.label)).capitalizedFirst,
                eyebrow: "Possible today", big: nil, items: symptoms,
                phase: phase, cycleDay: day, footer: footer, sharerLine: sharer))
        }

        if let phase, let headline {
            cards.append(ShareCard(
                kind: .phase, style: .moon, pickerTitle: "Phase",
                pickerSummary: "\(phase.rawValue.capitalized), \(headline.lowercasedFirst)",
                eyebrow: "Phase \(phase.phaseNumber) of 4", big: headline,
                detail: "\(phase.rawValue.capitalized) phase. \(phaseRest(phase))",
                phase: phase, cycleDay: day, footer: footer, sharerLine: sharer))
        }

        let best = input.mode == .planning ? bestChances(input) : nil
        if let best {
            cards.append(ShareCard(
                kind: .bestChances, style: .moon, pickerTitle: "Best chances",
                pickerSummary: best.summary,
                eyebrow: best.eyebrow, big: best.big, bigSide: best.side,
                detail: best.detail, estimateLine: TemplateInsightWriter.estimateLine,
                disclaimer: PlanningInsightsView.disclaimer,
                phase: phase, cycleDay: day, footer: footer, sharerLine: sharer))
        }

        var lines: [ShareCard.Fact] = []
        if let rest = periodRest(facts) { lines.append(.init(lead: "Period", rest: rest)) }
        if !symptoms.isEmpty { lines.append(.init(lead: "Possible today", rest: listed(symptoms.map(\.label)))) }
        if let best { lines.append(.init(lead: "Best chances", rest: best.combinedRest)) }
        for (kind, style, title, summary) in [(ShareCard.Kind.combined, ShareCard.Style.aura, "Everything on one card",
                                               "Day, phase and what may come next"),
                                              (.minimal, .minimal, "Minimal card", "The same, on a plain card")] {
            cards.append(ShareCard(
                kind: kind, style: style, pickerTitle: title, pickerSummary: summary,
                eyebrow: "My cycle today", big: "\(day)",
                bigSide: phase.map { $0.rawValue.capitalized }, bigSideDetail: headline,
                facts: lines, estimateLine: best == nil ? nil : TemplateInsightWriter.estimateLine,
                disclaimer: PlanningInsightsView.disclaimer,
                phase: phase, cycleDay: day, footer: footer, sharerLine: sharer))
        }
        return cards
    }

    /// "Period in about 3 days", "Period may start today", "Period 2 days later than estimated"; nil when unknown.
    private static func periodLine(_ facts: InsightFacts) -> String? {
        periodRest(facts).map { "Period \($0)" }
    }

    private static func periodRest(_ facts: InsightFacts) -> String? {
        if let late = facts.periodLateDays {
            return late == 1 ? "1 day later than estimated" : "\(late) days later than estimated"
        }
        guard let until = facts.daysUntilPeriod else { return nil }
        switch until {
        case 0:  return "may start today"
        case 1:  return "may start tomorrow"
        default: return "in about \(until) days"
        }
    }

    /// The template's phase line, never a written one (a written line may name the person's own tags).
    /// "Turn inward" from "Turn inward. Energy may soften before your period. Go gently."
    private static func phaseHeadline(_ phase: Event.EventType) -> String {
        let line = TemplateInsightWriter.moodLine(for: InsightFacts(mode: .cycle, phase: phase))
        return String(line.split(separator: ".", maxSplits: 1).first ?? Substring(line))
    }

    private static func phaseRest(_ phase: Event.EventType) -> String {
        let line = TemplateInsightWriter.moodLine(for: InsightFacts(mode: .cycle, phase: phase))
        guard let dot = line.range(of: ". ") else { return line }
        return String(line[dot.upperBound...])
    }

    /// The phase's common symptoms the Possible today tile lists, with the tile's symbols.
    private static func possibleToday(_ input: ShareCardInput) -> [ShareCard.Item] {
        guard let tile = input.insights.tile(.possibleToday), let phase = input.facts.phase else { return [] }
        let names = Array((TagFormLogic.phaseSymptomSuggestions[phase] ?? []).prefix(3))
        return names.enumerated().map { index, name in
            ShareCard.Item(symbol: index < tile.symbols.count ? tile.symbols[index] : "circle", label: name)
        }
    }

    private struct Best {
        let eyebrow: String
        let big: String
        let side: String?
        let detail: String?
        let summary: String
        let combinedRest: String
    }

    /// From the Fertile window tile and the days until the window; nil without an upcoming or current window.
    private static func bestChances(_ input: ShareCardInput) -> Best? {
        guard let tile = input.insights.tile(.fertile) else { return nil }
        let estimate = " " + TemplateInsightWriter.estimateLine
        let detail = tile.body.hasSuffix(estimate) ? String(tile.body.dropLast(estimate.count)) : tile.body
        if input.fertileToday {
            return Best(eyebrow: "Best chances", big: "Now", side: nil, detail: detail,
                        summary: "Now, inside your estimated window", combinedRest: "now")
        }
        guard let days = input.fertileStartsIn, days > 0 else { return nil }
        let unit = days == 1 ? "day" : "days"
        return Best(eyebrow: "Best chances in about", big: "\(days)", side: unit, detail: detail,
                    summary: "In about \(days) \(unit), an estimate", combinedRest: "in about \(days) \(unit)")
    }

    // MARK: - Menopause

    private static func menopauseCards(_ input: ShareCardInput, sharer: String?) -> [ShareCard] {
        let facts = input.facts
        guard input.insights.tile(.menopauseSymptoms) != nil, let thisWeek = facts.hotFlashesThisWeek else { return [] }
        let lastWeek = facts.hotFlashesLastWeek ?? 0
        var cards = [ShareCard(
            kind: .hotFlashes, style: .moon, pickerTitle: "Hot flashes",
            pickerSummary: "\(thisWeek) this week, \(lastWeek) last week",
            eyebrow: "Hot flashes this week", big: "\(thisWeek)",
            detail: "\(lastWeek) last week.", footer: footer, sharerLine: sharer)]

        var lines = [ShareCard.Fact(lead: "Last week", rest: lastWeek == 1 ? "1 hot flash" : "\(lastWeek) hot flashes")]
        if let hours = facts.sleepAverageHours {
            lines.append(.init(lead: "Sleep", rest: "\(SleepInsights.hoursText(hours)) a night on average"))
        }
        for (kind, style, title, summary) in [(ShareCard.Kind.combined, ShareCard.Style.aura, "Everything on one card",
                                               "This week on one card"),
                                              (.minimal, .minimal, "Minimal card", "The same, on a plain card")] {
            cards.append(ShareCard(
                kind: kind, style: style, pickerTitle: title, pickerSummary: summary,
                eyebrow: "My week", big: "\(thisWeek)",
                bigSide: thisWeek == 1 ? "hot flash" : "hot flashes", bigSideDetail: "this week",
                facts: lines, footer: footer, sharerLine: sharer))
        }
        return cards
    }

    // MARK: - Text

    /// "a, b, c" in lower case after the first word's capital is dropped: "mood swings, breast tenderness".
    static func listed(_ names: [String]) -> String {
        names.map { $0.lowercased() }.joined(separator: ", ")
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
