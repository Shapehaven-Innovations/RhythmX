//  InsightRevealViews.swift
//  The moving parts of the daily insight pull-up: the text that reveals line by line under a soft shimmer
//  (a TextRenderer over the real line layout), the "Where you are" chart whose curves draw themselves left to
//  right and whose marker glows, the breathing moon in the header and the sheet's aura background. Every part
//  takes its moment from `InsightReveal`, so a screenshot can render any point of the animation.

import Charts
import SwiftUI

// MARK: - Text

/// Draws each laid-out line up to its reveal progress with a feathered edge, and a moonlit shimmer at the edge.
/// While text streams in, every line is shown and the shimmer sweeps the last line.
struct RevealTextRenderer: TextRenderer {
    var elapsed: Double
    var reveal: InsightReveal
    var streaming: Bool
    /// 0 to 1, the streaming shimmer's position on the last line.
    var sweep: Double
    var glint: Color

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let lines = Array(layout)
        for (index, line) in lines.enumerated() {
            let progress = streaming ? 1 : reveal.lineProgress(index, at: elapsed)
            guard progress > 0 else { continue }
            let rect = line.typographicBounds.rect
            let shimmer: Double? = streaming
                ? (index == lines.count - 1 ? sweep : nil)
                : InsightReveal.shimmerCenter(lineProgress: progress)
            if progress >= 1 && shimmer == nil {
                ctx.draw(line)
                continue
            }
            ctx.drawLayer { layer in
                layer.draw(line)
                let midY = rect.midY
                if progress < 1 {
                    let edge = rect.minX + rect.width * progress
                    layer.blendMode = .destinationIn
                    layer.fill(Path(rect.insetBy(dx: -6, dy: -6)),
                               with: .linearGradient(Gradient(colors: [.black, .clear]),
                                                     startPoint: CGPoint(x: edge - 30, y: midY),
                                                     endPoint: CGPoint(x: edge, y: midY)))
                }
                if let shimmer {
                    let x = rect.minX + rect.width * shimmer - 18
                    layer.blendMode = .sourceAtop
                    layer.fill(Path(rect.insetBy(dx: -6, dy: -6)),
                               with: .linearGradient(Gradient(colors: [.clear, glint, .clear]),
                                                     startPoint: CGPoint(x: x - 34, y: midY),
                                                     endPoint: CGPoint(x: x + 34, y: midY)))
                }
            }
        }
    }
}

struct InsightRevealText: View {
    let text: String
    let elapsed: Double
    let reveal: InsightReveal
    var streaming: Bool = false
    var sweep: Double = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundColor(DS.Color.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textRenderer(RevealTextRenderer(elapsed: elapsed, reveal: reveal, streaming: streaming, sweep: sweep,
                                             glint: DS.Color.moon.opacity(colorScheme == .dark ? 0.95 : 0.85)))
            .accessibilityLabel(text)
    }
}

// MARK: - Chart

/// "Where you are": typical curves (Cycle, Planning) or the 8-week trend (Menopause).
struct InsightCurveChart: View {
    let chart: InsightDetailContent.Chart
    /// 0 to 1, how much of the curve is drawn.
    let progress: Double
    /// 0 to 1, the marker's glow.
    let glow: Double

    var body: some View {
        switch chart {
        case let .hormones(day, length, band):
            hormones(day: day, length: length, band: band)
        case let .menopauseTrend(weeks):
            trend(weeks)
        case .none:
            EmptyView()
        }
    }

    private static let yDomain: ClosedRange<Double> = -16...106

    private func hormones(day: Int, length: Int, band: ClosedRange<Double>?) -> some View {
        let marker = HormoneCurve.marker(day: day, length: length)
        let xDomain = 0.5...(Double(length) + 0.5)
        let markerShown = min(max((progress - marker.xFraction) * 8, 0), 1)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack {
                // Band, grid and the phase bars, always there.
                Chart {
                    if let band {
                        RectangleMark(xStart: .value("Day", band.lowerBound - 0.5), xEnd: .value("Day", band.upperBound + 0.5),
                                      yStart: .value("Level", 0), yEnd: .value("Level", 102))
                            .foregroundStyle(DS.Color.phase3.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    ForEach([25.0, 50.0, 75.0], id: \.self) { y in
                        RuleMark(y: .value("Level", y))
                            .foregroundStyle(DS.Color.separator.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 0.5))
                    }
                    ForEach(HormoneCurve.phaseBands(length: length), id: \.phase) { item in
                        RectangleMark(xStart: .value("Day", Double(item.days.lowerBound) - 0.35),
                                      xEnd: .value("Day", Double(item.days.upperBound) + 0.35),
                                      yStart: .value("Level", -14), yEnd: .value("Level", -9))
                            .foregroundStyle(item.phase.defaultPhaseColor)
                            .clipShape(Capsule())
                    }
                }
                .chartScaled(x: xDomain, y: Self.yDomain)

                // The curves, drawn in from the left.
                Chart {
                    LinePlot(x: "Day", y: "LH", domain: 1...Double(length)) { HormoneCurve.level(.lh, day: $0, length: length) }
                        .foregroundStyle(by: .value("Hormone", "LH"))
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [4, 4]))
                    LinePlot(x: "Day", y: "Estrogen", domain: 1...Double(length)) { HormoneCurve.level(.estrogen, day: $0, length: length) }
                        .foregroundStyle(by: .value("Hormone", "Estrogen"))
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    LinePlot(x: "Day", y: "Progesterone", domain: 1...Double(length)) { HormoneCurve.level(.progesterone, day: $0, length: length) }
                        .foregroundStyle(by: .value("Hormone", "Progesterone"))
                        .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
                .chartForegroundStyleScale(["LH": DS.Color.phase3, "Estrogen": DS.Color.phase2,
                                            "Progesterone": DS.Color.accent])
                .chartScaled(x: xDomain, y: Self.yDomain)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().frame(width: geo.size.width * progress)
                    }
                }

                // Today: the dotted rule and the glowing marker.
                Chart {
                    RuleMark(x: .value("Day", Double(marker.day)), yStart: .value("Level", -6), yEnd: .value("Level", 104))
                        .foregroundStyle(DS.Color.primaryText.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                    PointMark(x: .value("Day", Double(marker.day)), y: .value("Level", marker.level))
                        .symbol {
                            ZStack {
                                Circle().fill(DS.Color.accent.opacity(0.16 + 0.22 * glow))
                                    .frame(width: 14 + 18 * glow, height: 14 + 18 * glow)
                                Circle().fill(DS.Color.accent)
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().strokeBorder(DS.Color.cardBackground, lineWidth: 2))
                            }
                        }
                        .annotation(position: .top, spacing: 8) {
                            Text("You").font(.caption2.weight(.bold)).foregroundColor(DS.Color.primaryText)
                        }
                }
                .chartScaled(x: xDomain, y: Self.yDomain)
                .opacity(markerShown)
            }
            .frame(height: 128)

            HStack {
                Text("Day 1")
                Spacer()
                Text("\(length / 2)")
                Spacer()
                Text("\(length)")
            }
            .font(.caption2)
            .foregroundColor(DS.Color.secondaryText)
            .accessibilityHidden(true)

            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HormoneCurve.summary(day: day, length: length))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Progesterone", color: DS.Color.accent, dashed: false)
            legendItem("Estrogen", color: DS.Color.phase2, dashed: false)
            legendItem("LH", color: DS.Color.phase3, dashed: true)
        }
        .font(.caption)
        .foregroundColor(DS.Color.primaryText)
    }

    private func legendItem(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: dashed ? [3, 3] : []))
                .frame(width: 14, height: 1)
            Text(title)
        }
    }

    private func trend(_ weeks: [Int]) -> some View {
        let peak = Double(max(weeks.max() ?? 1, 1))
        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, count in
                    BarMark(x: .value("Week", index), y: .value("Hot flashes", Double(count) * progress), width: .ratio(0.55))
                        .foregroundStyle(index == weeks.count - 1 ? DS.Color.accent : DS.Color.accent.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .chartYScale(domain: 0...(peak * 1.15))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 110)
            HStack {
                Text("8 weeks ago")
                Spacer()
                Text("This week")
            }
            .font(.caption2)
            .foregroundColor(DS.Color.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hot flashes in each of the last 8 weeks: \(weeks.map(String.init).joined(separator: ", ")). This week \(weeks.last ?? 0).")
    }
}

private extension View {
    /// The same plot area in every layer: fixed domains, no axes, no legend.
    func chartScaled(x: ClosedRange<Double>, y: ClosedRange<Double>) -> some View {
        self.chartXScale(domain: x)
            .chartYScale(domain: y)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartPlotStyle { $0.frame(maxWidth: .infinity, maxHeight: .infinity) }
    }
}

// MARK: - Moon

/// The day's phase moon, drifting and breathing in its glow. Still with Reduce Motion.
struct BreathingMoonBadge: View {
    let phase: Event.EventType?
    var size: CGFloat = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = phase?.defaultPhaseColor ?? DS.Color.accent
        let moon = ZStack {
            Circle()
                .fill(RadialGradient(colors: [DS.Color.moon.opacity(0.7), DS.Color.moon.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size * 0.62))
                .frame(width: size * 1.25, height: size * 1.25)
            Circle()
                .fill(DS.Color.cardBackground.opacity(0.55))
                .overlay(Circle().strokeBorder(color.opacity(0.6), lineWidth: 1))
                .frame(width: size * 0.74, height: size * 0.74)
            MoonPhaseView(phase: phase?.moonPhase ?? .full, color: color, size: size * 0.74)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)

        if reduceMotion {
            moon
        } else {
            moon.phaseAnimator([false, true]) { content, up in
                content
                    .scaleEffect(up ? 1.04 : 1)
                    .offset(y: up ? -2 : 1)
            } animation: { _ in .easeInOut(duration: 3) }
        }
    }
}

// MARK: - Background

/// The sheet's background: the page colour under a wash of the phase colour, and a few glints.
struct InsightSheetBackground: View {
    let phase: Event.EventType?

    var body: some View {
        let tint = phase?.defaultPhaseColor ?? DS.Color.accent
        ZStack(alignment: .top) {
            DS.Color.pageBackground
            LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.06), .clear], startPoint: .top, endPoint: .center)
            Canvas { ctx, size in
                for (x, y, s) in [(0.76, 40.0, 5.0), (0.9, 92.0, 3.5), (0.1, 70.0, 4.0), (0.53, 22.0, 3.0)] {
                    ctx.fill(AuraStarCanvas.glint(x: x * size.width, y: y, size: s), with: .color(DS.Color.moon.opacity(0.7)))
                }
            }
            .frame(height: 140)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
