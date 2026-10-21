//  DailyInsightTileView.swift
//  One tile of "My daily insights" on Today. The text comes from `DailyInsightsService`; the numbers the tile
//  draws large (cycle day, days to the window, sleep) come from the same stores the text was written from.

import SwiftUI

/// The numbers a tile may draw besides its text.
struct DailyInsightTileContext {
    var phase: Event.EventType?
    var cycleDay: Int?
    var fertileToday: Bool = false
    var fertileStartsIn: Int?
    /// Menopause: hot flashes per week, oldest first.
    var hotFlashWeeks: [Int] = []
    var sleepHours: Double?
}

struct DailyInsightTileView: View {
    let tile: DailyInsightTile
    let context: DailyInsightTileContext
    /// Full width (accessibility text sizes stack the tiles).
    var stacked: Bool = false

    static let width: CGFloat = 140
    static let height: CGFloat = 164
    /// The big number follows Dynamic Type; in a fixed width tile it stops at 60 pt and shrinks to fit.
    @ScaledMetric(relativeTo: .largeTitle) private var bigSize: CGFloat = 44
    static let bigSizeCap: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            if tile.isAI {
                Label("Written on this device", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DS.Color.secondaryText)
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .padding(13)
        .frame(width: stacked ? nil : Self.width, alignment: .topLeading)
        .frame(maxWidth: stacked ? .infinity : nil, minHeight: Self.height, alignment: .topLeading)
        .background(background)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(tile.kind == .logPrompt ? "Opens Add Tag" : "Shows the full insight")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Background

    private var tint: Color? {
        switch tile.kind {
        case .cycleDay:          return (context.phase ?? .luteal).defaultPhaseColor.opacity(0.24)
        case .fertile:           return DS.Color.phase3.opacity(0.26)
        case .pattern:           return DS.Color.accent.opacity(0.09)
        case .menopauseSymptoms: return DS.Color.accent.opacity(0.10)
        default:                 return nil
        }
    }

    private var background: some View {
        ZStack {
            CardSurface(cornerRadius: 24)
            if let tint {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(tint)
            }
            if tile.kind == .logPrompt {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(DS.Color.accent.opacity(0.22), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Content

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(DS.Color.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func caption(_ text: String, lines: Int? = 3) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(DS.Color.secondaryText)
            .lineLimit(stacked ? nil : lines)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func big(_ text: String) -> some View {
        Text(text)
            .font(.system(size: stacked ? bigSize : min(bigSize, Self.bigSizeCap), weight: .bold).monospacedDigit())
            .foregroundColor(DS.Color.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.top, 4)
    }

    @ViewBuilder
    private var content: some View {
        switch tile.kind {
        case .logPrompt:
            Text(tile.title).font(.headline).foregroundColor(DS.Color.primaryText)
            caption(firstSentence(tile.body), lines: 2).padding(.top, 2)
            Spacer(minLength: DS.Spacing.sm)
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundColor(DS.Color.onAccent)
                .frame(width: 46, height: 46)
                .background(Circle().fill(DS.Color.accent))
        case .cycleDay:
            title("Cycle day")
            big(context.cycleDay.map(String.init) ?? "-")
            Spacer(minLength: DS.Spacing.xs)
            if let phase = context.phase {
                HStack(spacing: 6) {
                    Circle().fill(phase.defaultPhaseColor).frame(width: 8, height: 8)
                    Text(phase.rawValue.capitalized).font(.footnote).foregroundColor(DS.Color.primaryText)
                }
            }
        case .possibleToday:
            title(tile.title)
            HStack(spacing: -6) {
                ForEach(Array(tile.symbols.prefix(3).enumerated()), id: \.offset) { _, symbol in
                    Image(systemName: symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(DS.Color.primaryText)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill((context.phase ?? .luteal).defaultPhaseColor.opacity(0.22)))
                        .background(Circle().fill(DS.Color.cardBackground))
                        .overlay(Circle().strokeBorder(DS.Color.cardBackground, lineWidth: 2))
                }
            }
            .padding(.top, DS.Spacing.sm)
            Spacer(minLength: DS.Spacing.xs)
            caption(listPart(tile.body))
        case .fertile:
            title(context.fertileToday ? "Fertile window" : "Best chances in")
            big(context.fertileToday ? "Now" : (context.fertileStartsIn.map { "\($0) d" } ?? "-"))
            Spacer(minLength: DS.Spacing.xs)
            caption("An estimate. Not birth control.")
        case .energy:
            title(tile.title)
            energyBars.padding(.top, DS.Spacing.sm)
            Spacer(minLength: DS.Spacing.xs)
            caption(tile.body)
        case .menopauseSymptoms:
            title(tile.title)
            Sparkline(values: Array(context.hotFlashWeeks.suffix(7)))
                .stroke(DS.Color.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(height: 44)
                .padding(.top, DS.Spacing.sm)
            Spacer(minLength: DS.Spacing.xs)
            caption(tile.body)
        case .sleep:
            title(tile.title)
            big(context.sleepHours.map { SleepInsights.hoursText($0) } ?? "-")
            Spacer(minLength: DS.Spacing.xs)
            HStack(spacing: 4) {
                Image(systemName: "heart").foregroundColor(DS.Color.phase1)
                Text("From Apple Health")
            }
            .font(.caption)
            .foregroundColor(DS.Color.secondaryText)
        case .pattern:
            title(tile.title)
            Text(tile.body)
                .font(.footnote)
                .foregroundColor(DS.Color.primaryText)
                .lineLimit(stacked ? nil : 5)
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
    }

    private var energyBars: some View {
        let level: Int = {
            switch context.phase {
            case .menstrual?: return 1
            case .follicular?: return 3
            case .ovulation?: return 5
            case .luteal?: return 2
            case nil: return 0
            }
        }()
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(i < level ? (context.phase ?? .luteal).defaultPhaseColor : Color(UIColor.tertiarySystemFill))
                    .frame(width: 14, height: CGFloat(14 + i * 8))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Text helpers

    private func firstSentence(_ text: String) -> String {
        guard let end = text.range(of: "? ") ?? text.range(of: ". ") else { return text }
        return String(text[..<end.lowerBound]) + String(text[end.lowerBound])
    }

    /// "Common in this phase: Bloating, Cravings and Tender Breasts." shows as the list only.
    private func listPart(_ text: String) -> String {
        guard let colon = text.range(of: ": ") else { return text }
        return String(text[colon.upperBound...])
    }

    private var accessibilityLabel: String {
        switch tile.kind {
        case .cycleDay:
            return [tile.title, context.phase.map { "\($0.rawValue.capitalized) phase" }].compactMap { $0 }.joined(separator: ", ")
        case .fertile:
            return "\(tile.title). \(tile.body)"
        default:
            return "\(tile.title). \(tile.body)" + (tile.isAI ? " Written on this device." : "")
        }
    }
}

/// A small line chart through `values`, scaled to its frame.
struct Sparkline: Shape {
    let values: [Int]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let peak = Double(max(values.max() ?? 1, 1))
        for (i, v) in values.enumerated() {
            let point = CGPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1),
                                y: rect.maxY - rect.height * CGFloat(Double(v) / peak) * 0.9 - 2)
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}
