//  TodayHeroView.swift
//  The breathing moon on Today: the phase ring (or, in Menopause, the week's seven days) around a luminous
//  disc that holds the day's headline and the main action. At accessibility text sizes the words move out of
//  the disc and sit under a smaller ring.

import SwiftUI

struct TodayHeroView: View {
    let hero: TodayHero
    let mode: TrackingMode
    let snapshot: PhaseWidgetSnapshot
    /// Menopause: tags logged on each of the last seven days, oldest first.
    let menopauseDays: [Int]
    let palette: AuraPalette
    var actionTitle: String? = nil
    var actionDisabled: Bool = false
    let onAction: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Breathing runs on the shared low rate clock, only while `AmbientMotionScope` allows it.
    @Environment(\.ambientMotion) private var ambientMotion
    /// The headline follows Dynamic Type. Inside the disc it stops at 58 pt (it also shrinks to fit); under the
    /// smaller ring at accessibility sizes it can grow to 76 pt.
    @ScaledMetric(relativeTo: .largeTitle) private var discHeadline: CGFloat = 46
    @ScaledMetric(relativeTo: .largeTitle) private var openHeadline: CGFloat = 40

    static let ringSize: CGFloat = 254
    static let discSize: CGFloat = 228
    static let ringWidth: CGFloat = 5

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: DS.Spacing.md) {
                ring(size: 168, disc: 150) {
                    MoonPhaseView(phase: (snapshot.phase ?? .ovulation).moonPhase,
                                  color: snapshot.phase.map(\.defaultPhaseColor) ?? DS.Color.accent,
                                  isActive: snapshot.phase != nil, size: 44)
                }
                words(compact: false)
                actionButton
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.Spacing.md)
        } else {
            ring(size: Self.ringSize, disc: Self.discSize) {
                VStack(spacing: 2) {
                    words(compact: true)
                    actionButton.padding(.top, DS.Spacing.sm)
                }
                .frame(width: Self.discSize * 0.80)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.ringSize + 8)
        }
    }

    // MARK: - Ring and disc

    private func ring<Content: View>(size: CGFloat, disc: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let glow = DS.Color.solid(palette.glow)
        return ZStack {
            // Glow and disc breathe together, slowly, on the 15 fps clock (still when motion is off).
            TimelineView(.animation(minimumInterval: AmbientMotion.minimumInterval, paused: !ambientMotion)) { timeline in
                let t: Double? = ambientMotion ? timeline.date.timeIntervalSinceReferenceDate : nil
                discView(diameter: disc, glow: glow, breath: AmbientMotion.breath(at: t))
            }

            Group {
                if mode == .menopause { weekRing(size: size) } else { phaseRing(size: size) }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)

            content()
        }
    }

    private func discView(diameter: CGFloat, glow: Color, breath: Double) -> some View {
        let colors: [Color] = [DS.Color.solid(palette.discLight), DS.Color.solid(palette.discBody),
                               DS.Color.solid(RGB.mix(palette.discBody, palette.glow, 0.16))]
        let fill = RadialGradient(colors: colors, center: UnitPoint(x: 0.36, y: 0.28), startRadius: 0,
                                  endRadius: diameter * 0.78)
        let highlight = LinearGradient(colors: [CardSurface.highlight, .clear], startPoint: .top, endPoint: .center)
        let glowOpacity: Double = 0.30 + 0.12 * breath
        let glowRadius: CGFloat = 26 + 8 * CGFloat(breath)
        let scale: CGFloat = 1 + 0.03 * CGFloat(breath)
        return Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(DS.Color.solid(palette.disc).opacity(0.7), lineWidth: 1.5))
            .overlay(Circle().strokeBorder(highlight, lineWidth: 1))
            .frame(width: diameter, height: diameter)
            .shadow(color: glow.opacity(glowOpacity), radius: glowRadius)
            .scaleEffect(scale)
    }

    private struct Arc: Identifiable {
        let phase: Event.EventType
        let start: Double
        let end: Double
        var id: Event.EventType { phase }
    }

    private var cycleLength: Int { max(snapshot.cycleLength ?? snapshot.averageCycleLength ?? 28, 16) }

    private var arcs: [Arc] {
        let counts = CycleGenerator.dayCounts(cycleLength: cycleLength)
        let total = Double(max(counts.values.reduce(0, +), 1))
        var cursor = 0.0
        return Event.EventType.allCases.map { phase in
            let span = Double(counts[phase] ?? 0) / total
            defer { cursor += span }
            return Arc(phase: phase, start: cursor, end: cursor + span)
        }
    }

    private func phaseRing(size: CGFloat) -> some View {
        let radius = (size - Self.ringWidth) / 2
        let circumference = 2 * .pi * radius
        // Round caps reach half a line width past each end; leave a 5 pt gap between arcs.
        let inset = Double((5 / 2 + Self.ringWidth / 2) / circumference)
        return ZStack {
            ForEach(arcs) { arc in
                Circle()
                    .trim(from: arc.start + inset, to: max(arc.start + inset, arc.end - inset))
                    .stroke(arc.phase.defaultPhaseColor, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(Self.ringWidth / 2)
            }
            if let day = snapshot.cycleDay, let phase = snapshot.phase {
                let angle = (Double(day) - 0.5) / Double(cycleLength) * 2 * .pi - .pi / 2
                ZStack {
                    Circle().fill(phase.defaultPhaseColor.opacity(0.22)).frame(width: 19, height: 19)
                    Circle().fill(DS.Color.cardBackground).frame(width: 15, height: 15)
                    Circle().fill(phase.defaultPhaseColor).frame(width: 10.5, height: 10.5)
                }
                .offset(x: radius * cos(angle), y: radius * sin(angle))
            }
        }
    }

    /// Menopause: seven arcs for the last seven days, stronger where more was logged.
    private func weekRing(size: CGFloat) -> some View {
        let radius = (size - Self.ringWidth) / 2
        let inset = Double((8 / 2 + Self.ringWidth / 2) / (2 * .pi * radius))
        let peak = max(menopauseDays.max() ?? 0, 1)
        return ZStack {
            ForEach(0..<7, id: \.self) { i in
                let count = i < menopauseDays.count ? menopauseDays[i] : 0
                Circle()
                    .trim(from: Double(i) / 7 + inset, to: Double(i + 1) / 7 - inset)
                    .stroke(DS.Color.accent.opacity(count == 0 ? 0.25 : 0.4 + 0.6 * Double(count) / Double(peak)),
                            style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(Self.ringWidth / 2)
            }
        }
    }

    // MARK: - Words

    private func words(compact: Bool) -> some View {
        VStack(spacing: 2) {
            Text(hero.eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(compact ? 1.6 : 2)
                .foregroundColor(DS.Color.secondaryText)
                // The disc narrows toward its top: keep the eyebrow inside the curve.
                .frame(maxWidth: compact ? Self.discSize * 0.66 : nil)
            Text(hero.lead)
                .font(compact ? .body : .title3)
                .foregroundColor(DS.Color.secondaryText)
                .padding(.top, 4)
            Text(hero.headline)
                .font(.system(size: compact ? min(discHeadline, 58) : min(openHeadline, 76), weight: .bold, design: .default))
                .foregroundColor(DS.Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let detail = hero.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(DS.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 1 : nil)
                    .minimumScaleFactor(compact ? 0.6 : 1)
            }
        }
        .lineLimit(compact ? 1 : nil)
        .minimumScaleFactor(compact ? 0.6 : 1)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [hero.eyebrow, "\(hero.lead) \(hero.headline)"]
        if let detail = hero.detail { parts.append(detail) }
        return parts.joined(separator: ". ")
    }

    private var actionButton: some View {
        Button(action: onAction) {
            Text(actionTitle ?? hero.action.title)
                .font(.headline)
                .foregroundStyle(DS.Color.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, DS.Spacing.sm)
                .frame(minHeight: 36)
        }
        .buttonStyle(.glassProminent)
        .tint(DS.Color.accent)
        .disabled(actionDisabled)
        .frame(minHeight: 44)
        .contentShape(Capsule())
    }
}
