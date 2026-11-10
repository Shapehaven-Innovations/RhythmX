//  SkinInsightsView.swift
//
//  The Skin screen (design 9.2): a face map with body tiles, or front and back silhouettes with callouts,
//  filtered by window and phase. Cells use `SkinRamp`; phase colours appear only as small pills over the
//  phase names. A small Intimacy card sits at the bottom (design 9.5).

import SwiftUI

struct SkinInsightsView: View {
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    var now: Date? = nil
    @State private var window: SkinStats.Window = .thirty
    @State private var phase: Event.EventType? = nil        // nil = All
    @State private var showsFullBody = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(now: Date? = nil) {
        self.now = now
    }

    private static let phases: [Event.EventType] = [.menstrual, .follicular, .ovulation, .luteal]
    private static let faceAreas: [SkinTag.Area] = [.forehead, .cheeks, .nose, .jaw, .chin, .face]
    private static let bodyTileAreas: [SkinTag.Area] = [.back, .chest, .shoulders, .neck, .arms]
    /// One representative percent per ramp bucket 1...5, for the legend.
    private static let legendPercents = [5, 15, 30, 45, 60]
    /// Face map width cap, so the face reads as in the mockup rather than filling a wide card.
    private static let faceMapMaxWidth: CGFloat = 260

    private var today: Date { now ?? Date() }
    private var isMenopause: Bool { appSettings.trackingMode == .menopause }
    /// The phase actually applied: none in Menopause.
    private var activePhase: Event.EventType? { isMenopause ? nil : phase }

    private func makeStats(window: SkinStats.Window) -> SkinStats {
        SkinStats(events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks,
                  today: today, window: window)
    }

    var body: some View {
        let stats = makeStats(window: window)
        let percents = stats.percentByArea(phase: activePhase)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Picker("Time window", selection: $window) {
                    Text("30 days").tag(SkinStats.Window.thirty)
                    Text("90 days").tag(SkinStats.Window.ninety)
                    Text("All").tag(SkinStats.Window.all)
                }
                .pickerStyle(.segmented)

                if !isMenopause {
                    phaseChips(stats)
                }

                Picker("View", selection: fullBodyBinding) {
                    Text("Face").tag(false)
                    Text("Full body").tag(true)
                }
                .pickerStyle(.segmented)

                if stats.loggedDays < SkinStats.minimumDaysForBody {
                    emptyCard
                } else if showsFullBody {
                    fullBodyCard(stats: stats, percents: percents)
                    topAreasCard(stats: stats, percents: percents)
                } else {
                    faceCard(stats: stats, percents: percents)
                    bodyTilesCard(percents: percents)
                }

                if !isMenopause {
                    byPhaseLink
                    if stats.intimacyByPhase().contains(where: { $0.flareDays > 0 }) {
                        intimacyCard(stats: stats)
                    }
                }
            }
            .padding(DS.Spacing.md)
        }
        .themedPage()
        .navigationTitle("Skin")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: window) { _, newWindow in
            // A phase that no longer has enough days in the new window falls back to All.
            if let phase, (makeStats(window: newWindow).loggedDaysByPhase[phase] ?? 0) < SkinStats.minimumDaysPerPhase {
                self.phase = nil
            }
        }
    }

    private var fullBodyBinding: Binding<Bool> {
        Binding(get: { showsFullBody }, set: { setFullBody($0) })
    }

    private func setFullBody(_ value: Bool) {
        if reduceMotion {
            showsFullBody = value
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { showsFullBody = value }
        }
    }

    // MARK: - Wording

    private var phaseWord: String { activePhase?.rawValue.capitalized ?? "All" }

    private var windowWord: String {
        switch window {
        case .days(let n): return "last \(n) days"
        case .all:         return "all time"
        }
    }

    private func subtitle(_ stats: SkinStats) -> String {
        let k = activePhase.map { stats.loggedDaysByPhase[$0] ?? 0 } ?? stats.loggedDays
        return "\(phaseWord) days · \(windowWord) · \(k) \(k == 1 ? "day" : "days") logged"
    }

    private static func percentText(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? "–"
    }

    // MARK: - Phase chips

    private func phaseChips(_ stats: SkinStats) -> some View {
        let chips = HStack(spacing: 2) {
            phaseChip(nil, enabled: true)
            ForEach(Self.phases) { p in
                phaseChip(p, enabled: (stats.loggedDaysByPhase[p] ?? 0) >= SkinStats.minimumDaysPerPhase)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
            .fill(DS.Color.primaryText.opacity(0.06)))
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) { chips }
            } else {
                chips
            }
        }
    }

    private func phaseChip(_ p: Event.EventType?, enabled: Bool) -> some View {
        let isSelected = phase == p
        let name = p?.rawValue.capitalized ?? "All"
        return Button {
            phase = p
        } label: {
            VStack(spacing: 4) {
                phasePill(p)
                Text(name)
                    .font(DS.Font.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(DS.Color.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, DS.Spacing.xs)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, minHeight: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.chip + 2, style: .continuous)
                        .fill(DS.Color.cardBackground)
                        .shadow(color: CardSurface.shadow, radius: 3, x: 0, y: 1)
                }
            }
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(p.map { "\($0.rawValue.capitalized) phase" } ?? "All phases")
        .accessibilityValue(enabled ? "" : "dimmed")
        .accessibilityHint(enabled ? "" : "Not enough days logged in this phase yet")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func phasePill(_ p: Event.EventType?) -> some View {
        if let p {
            Capsule().fill(p.phaseColor).frame(width: 18, height: 4)
        } else {
            HStack(spacing: 0) {
                ForEach(Self.phases) { Rectangle().fill($0.phaseColor) }
            }
            .frame(width: 18, height: 4)
            .clipShape(Capsule())
        }
    }

    // MARK: - Face view

    private func faceCard(stats: SkinStats, percents: [SkinTag.Area: Int?]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            cardHeader("Face", subtitle: subtitle(stats))
            FaceCalloutFigure(percents: percents, maxMapWidth: Self.faceMapMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.xs)
            legend
            if let area = topFaceArea(percents), let line = stats.comparisonLine(area: area) {
                comparisonText(line)
            }
        }
        .cardStyle()
    }

    /// The face area with the highest percentage under the current filter.
    private func topFaceArea(_ percents: [SkinTag.Area: Int?]) -> SkinTag.Area? {
        var best: (area: SkinTag.Area, percent: Int)?
        for area in Self.faceAreas {
            guard let p = percents[area] ?? nil, p > 0 else { continue }
            if best == nil || p > best!.percent { best = (area, p) }
        }
        return best?.area
    }

    /// "Chin 62%" in bold, the rest in secondary, as in the mockup.
    private func comparisonText(_ line: String) -> some View {
        let split = line.firstIndex(of: "%").map { line.index(after: $0) } ?? line.startIndex
        return (Text(line[..<split]).foregroundColor(DS.Color.primaryText).bold()
                + Text(line[split...]).foregroundColor(DS.Color.secondaryText))
            .font(DS.Font.label)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The head on the Full body map shows the highest percent among the face sub-areas (nil when all are nil),
    /// and which area that is.
    static func headValue(_ percents: [SkinTag.Area: Int?]) -> (area: SkinTag.Area, percent: Int)? {
        var best: (area: SkinTag.Area, percent: Int)?
        for area in faceAreas {
            guard let p = percents[area] ?? nil else { continue }
            if best == nil || p > best!.percent { best = (area, p) }
        }
        return best
    }

    private static func withHead(_ percents: [SkinTag.Area: Int?], _ head: Int?) -> [SkinTag.Area: Int?] {
        var map = percents
        map[.face] = .some(head)
        return map
    }

    private func bodyTilesCard(percents: [SkinTag.Area: Int?]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Body")
                    .font(DS.Font.sectionHeader)
                    .foregroundColor(DS.Color.primaryText)
                Spacer(minLength: DS.Spacing.sm)
                Button { setFullBody(true) } label: {
                    Text("Body graph ›")
                        .font(DS.Font.label)
                        .foregroundColor(DS.Color.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Body graph")
                .accessibilityHint("Shows the full body map")
            }
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: DS.Spacing.sm)], spacing: DS.Spacing.sm) {
                    ForEach(Self.bodyTileAreas) { area in bodyTile(area, percent: percents[area] ?? nil) }
                }
            } else {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(Self.bodyTileAreas) { area in bodyTile(area, percent: percents[area] ?? nil) }
                }
            }
        }
        .cardStyle()
    }

    private func bodyTile(_ area: SkinTag.Area, percent: Int?) -> some View {
        let text = SkinRamp.textColor(percent: percent)
        return VStack(spacing: 0) {
            Text(Self.percentText(percent))
                .font(DS.Font.sectionHeader.monospacedDigit())
            Text(area.rawValue)
                .font(DS.Font.micro.weight(.medium))
        }
        .foregroundColor(percent == nil ? DS.Color.secondaryText : text)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
            .fill(SkinRamp.fillColour(percent: percent)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(area.rawValue)
        .accessibilityValue(BodyMapView.spokenValue(percent))
    }

    // MARK: - Full body view

    private func fullBodyCard(stats: SkinStats, percents: [SkinTag.Area: Int?]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            cardHeader("Where it flares", subtitle: subtitle(stats))
            let head = Self.headValue(percents)
            BodyCalloutFigure(percents: Self.withHead(percents, head?.percent),
                              headSource: head?.area)
                .padding(.vertical, DS.Spacing.xs)
            legend
            Text("% of logged days with a flare-up in that area")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    @ViewBuilder
    private func topAreasCard(stats: SkinStats, percents: [SkinTag.Area: Int?]) -> some View {
        let rows = stats.topAreas(limit: 5)
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    topAreaRow(row, percent: percents[row.area] ?? nil)
                }
            }
            .cardStyle()
        }
    }

    private func topAreaRow(_ row: SkinStats.AreaRow, percent: Int?) -> some View {
        let isFace = Self.faceAreas.contains(row.area)
        let detail = [row.topKind?.rawValue, row.topColour?.rawValue].compactMap { $0?.lowercased() }
        let detailText = detail.isEmpty ? nil : "mostly " + detail.joined(separator: ", ")
        let swatch = Text(Self.percentText(percent))
            .font(DS.Font.label.weight(.bold).monospacedDigit())
            .foregroundColor(percent == nil ? DS.Color.secondaryText : SkinRamp.textColor(percent: percent))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 52, height: 32)
            .background(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(SkinRamp.fillColour(percent: percent)))
        let names = VStack(alignment: .leading, spacing: 0) {
            Text(row.area.rawValue)
                .font(DS.Font.body)
                .foregroundColor(DS.Color.primaryText)
            if let detailText {
                Text(detailText)
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.secondaryText)
            }
        }
        let trailing = Group {
            if isFace {
                Button { setFullBody(false) } label: {
                    Text("Face map ›")
                        .font(DS.Font.label)
                        .foregroundColor(DS.Color.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Face map")
                .accessibilityHint("Shows the face map")
            } else if let versus = versusText(row) {
                Text(versus)
                    .font(DS.Font.label)
                    .foregroundColor(DS.Color.secondaryText)
            }
        }
        let summary = Text("\(row.area.rawValue), \(BodyMapView.spokenValue(percent))"
                           + (detailText.map { ", \($0)" } ?? "")
                           + (versusText(row).map { ", \($0)" } ?? ""))
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack(spacing: DS.Spacing.sm) { swatch; names }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(summary)
                    trailing
                }
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.sm) {
                        swatch
                        names
                        Spacer(minLength: DS.Spacing.xs)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary)
                    trailing
                }
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: 44)
    }

    /// "vs 6% follicular": the lowest phase with enough days, other than the selected phase (or the peak).
    private func versusText(_ row: SkinStats.AreaRow) -> String? {
        guard !isMenopause else { return nil }
        let excluded: Set<Event.EventType> = activePhase.map { [$0] } ?? row.peak
        let valued = row.cells.filter { $0.percent != nil }
        guard valued.count >= 2 else { return nil }
        let candidates = valued.filter { !excluded.contains($0.phase) }
        guard let low = candidates.min(by: { $0.percent! < $1.percent! }), let q = low.percent else { return nil }
        return "vs \(q)% \(low.phase.rawValue)"
    }

    // MARK: - By phase, Intimacy, empty

    private var byPhaseLink: some View {
        NavigationLink {
            SkinPhaseGridView(events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks,
                              today: today, window: window)
        } label: {
            HStack {
                Text("By phase")
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DS.Font.label.weight(.semibold))
                    .foregroundColor(DS.Color.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows each area by cycle phase")
    }

    private func intimacyCard(stats: SkinStats) -> some View {
        let cells = stats.intimacyByPhase()
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Intimacy")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            HStack(spacing: DS.Spacing.xs) {
                ForEach(cells, id: \.phase) { cell in
                    VStack(spacing: 4) {
                        Capsule().fill(cell.phase.phaseColor).frame(width: 18, height: 4)
                        Text(cell.phase.rawValue.capitalized)
                            .font(DS.Font.micro)
                            .foregroundColor(DS.Color.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(Self.percentText(cell.percent))
                            .font(DS.Font.label.weight(.semibold).monospacedDigit())
                            .foregroundColor(cell.percent == nil ? DS.Color.secondaryText
                                             : SkinRamp.textColor(percent: cell.percent))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(SkinRamp.fillColour(percent: cell.percent)))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(cell.phase.rawValue.capitalized)
                    .accessibilityValue(BodyMapView.spokenValue(cell.percent))
                }
            }
            Text("% of logged days in that phase with Sex or Intercourse logged")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let line = stats.intimacySkinLine() {
                Text(line)
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private var emptyCard: some View {
        VStack(spacing: DS.Spacing.md) {
            Group {
                if showsFullBody {
                    HStack(spacing: DS.Spacing.lg) {
                        BodyMapView(side: .front, mode: .display(percentByArea: [:], showsLabels: false))
                        BodyMapView(side: .back, mode: .display(percentByArea: [:], showsLabels: false))
                    }
                    .frame(maxWidth: 220)
                } else {
                    BodyMapView(side: .face, mode: .display(percentByArea: [:], showsLabels: false))
                        .frame(maxWidth: 160)
                }
            }
            .accessibilityHidden(true)
            Text("Log your skin on a few days and this fills in.")
                .font(DS.Font.label)
                .foregroundColor(DS.Color.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - Shared pieces

    private func cardHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text(subtitle)
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var legend: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text("0%")
                .font(DS.Font.micro)
                .foregroundColor(DS.Color.secondaryText)
            HStack(spacing: 0) {
                ForEach(Self.legendPercents, id: \.self) { percent in
                    Rectangle()
                        .fill(SkinRamp.fillColour(percent: percent))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            Text("50%+")
                .font(DS.Font.micro)
                .foregroundColor(DS.Color.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Colour scale from 0 percent, lightest, to 50 percent or more, darkest")
    }
}

// MARK: - Front and back figure with callouts

/// Front and back silhouettes side by side. The maps are drawn without their own labels (at this size the
/// in-region text would be a few points high); this view prints callouts outside the figures with leader
/// lines, and labels the chest and back inside, as in mockup 2a. VoiceOver reads the maps' own elements.
private struct BodyCalloutFigure: View {
    let percents: [SkinTag.Area: Int?]
    /// The face sub-area whose percent the head shows.
    let headSource: SkinTag.Area?

    /// Callout column width on each side, as a share of the figure width (about 60pt on a 6.1" iPhone).
    private static let calloutShare: CGFloat = 0.18
    /// Share of each map's width that the callout column may overlap (the silhouettes' empty margin).
    private static let overlap: CGFloat = 0.10
    /// Map width as a share of the figure width.
    private static let mapShare: CGFloat = (1 - 2 * calloutShare) / (2 - 2 * overlap)

    private struct Callout: Identifiable {
        let area: SkinTag.Area
        let anchor: CGPoint     // unit point on the map
        let labelY: CGFloat     // unit y of the callout's centre
        var id: String { area.rawValue }
    }

    private static let frontCallouts = [
        Callout(area: .face, anchor: CGPoint(x: 0.36, y: 0.075), labelY: 0.05),
        Callout(area: .neck, anchor: CGPoint(x: 0.44, y: 0.17), labelY: 0.17),
        Callout(area: .shoulders, anchor: CGPoint(x: 0.22, y: 0.215), labelY: 0.29),
        Callout(area: .arms, anchor: CGPoint(x: 0.13, y: 0.40), labelY: 0.41),
    ]
    private static let backCallouts = [
        Callout(area: .shoulders, anchor: CGPoint(x: 0.78, y: 0.215), labelY: 0.215),
        Callout(area: .arms, anchor: CGPoint(x: 0.87, y: 0.40), labelY: 0.40),
    ]

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            GeometryReader { geo in
                let w = geo.size.width
                let c = Self.calloutShare * w
                let m = Self.mapShare * w
                let h = m * BodyMapShapes.bodyAspect
                let frontX = c - Self.overlap * m
                let backX = frontX + m
                ZStack(alignment: .topLeading) {
                    BodyMapView(side: .front, mode: .display(percentByArea: percents, showsLabels: false), width: m,
                                spokenValueOverrides: headSpokenValue)
                        .offset(x: frontX)
                    BodyMapView(side: .back, mode: .display(percentByArea: percents, showsLabels: false), width: m)
                        .offset(x: backX)

                    Group {
                        insideLabel(.chest, at: CGPoint(x: frontX + 0.5 * m, y: 0.33 * h))
                        insideLabel(.back, at: CGPoint(x: backX + 0.5 * m, y: 0.38 * h))

                        ForEach(Self.frontCallouts) { callout in
                            let anchor = CGPoint(x: frontX + callout.anchor.x * m, y: callout.anchor.y * h)
                            let labelY = callout.labelY * h
                            leader(from: CGPoint(x: c - 2, y: labelY), to: anchor)
                            calloutLabel(callout.area, alignment: .trailing)
                                .frame(width: c - 4, alignment: .trailing)
                                .position(x: (c - 4) / 2, y: labelY)
                        }
                        ForEach(Self.backCallouts) { callout in
                            let anchor = CGPoint(x: backX + callout.anchor.x * m, y: callout.anchor.y * h)
                            let labelY = callout.labelY * h
                            let columnX = w - c
                            leader(from: CGPoint(x: columnX + 2, y: labelY), to: anchor)
                            calloutLabel(callout.area, alignment: .leading)
                                .frame(width: c - 4, alignment: .leading)
                                .position(x: columnX + 4 + (c - 4) / 2, y: labelY)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .aspectRatio(1 / (Self.mapShare * BodyMapShapes.bodyAspect), contentMode: .fit)

            // FRONT and BACK under the centre of each map.
            GeometryReader { geo in
                let m = Self.mapShare * geo.size.width
                let frontX = Self.calloutShare * geo.size.width - Self.overlap * m
                sideCaption("FRONT").position(x: frontX + 0.5 * m, y: 8)
                sideCaption("BACK").position(x: frontX + 1.5 * m, y: 8)
            }
            .frame(height: 16)
            .accessibilityHidden(true)
        }
    }

    private func value(_ area: SkinTag.Area) -> Int? { percents[area] ?? nil }

    /// The head region reads "Face, most affected: chin 62%" once; the printed callout is hidden from VoiceOver.
    private var headSpokenValue: [SkinTag.Area: String] {
        guard let source = headSource, let percent = value(.face) else { return [:] }
        return [.face: "most affected: \(source.rawValue.lowercased()) \(percent)%"]
    }

    private func calloutLabel(_ area: SkinTag.Area, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(area.rawValue)
                .font(.system(size: 10))
                .foregroundColor(DS.Color.secondaryText)
            Text(value(area).map { "\($0)%" } ?? "–")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundColor(DS.Color.primaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func insideLabel(_ area: SkinTag.Area, at point: CGPoint) -> some View {
        let percent = value(area)
        return VStack(spacing: 0) {
            Text(area.rawValue)
                .font(.system(size: 11, weight: .semibold))
            Text(percent.map { "\($0)%" } ?? "–")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
        }
        .foregroundColor(percent == nil ? DS.Color.secondaryText : SkinRamp.textColor(percent: percent))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .position(point)
    }

    private func leader(from start: CGPoint, to end: CGPoint) -> some View {
        Path { p in
            p.move(to: start)
            p.addLine(to: end)
        }
        .stroke(DS.Color.secondaryText.opacity(0.5), lineWidth: 0.75)
    }

    private func sideCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.2)
            .foregroundColor(DS.Color.secondaryText)
    }
}

// MARK: - Face map with callouts

/// The face map with the wide regions (forehead, cheeks, chin) labelled inside, and the small ones (nose, jaw)
/// plus the whole-face band labelled outside with leader lines, so no label is cramped or clipped.
/// VoiceOver reads the map's own region elements; the callouts are hidden from it.
private struct FaceCalloutFigure: View {
    let percents: [SkinTag.Area: Int?]
    let maxMapWidth: CGFloat

    /// Callout column width on each side, as a share of the figure width.
    private static let calloutShare: CGFloat = 0.17
    /// Share of the map's width the callout column may overlap (the margin left and right of the face oval).
    private static let overlap: CGFloat = 0.08
    private static let mapShare: CGFloat = (1 - 2 * calloutShare) / (1 - 2 * overlap)
    private static let calloutAreas: Set<SkinTag.Area> = [.nose, .jaw, .face]

    private struct Callout: Identifiable {
        let id: String
        let area: SkinTag.Area
        let anchor: CGPoint     // unit point on the map, inside the region
        let labelY: CGFloat     // unit y of the callout's centre
        let leading: Bool       // true: left column
    }

    /// Anchors sit in each region's widest visible part; label heights keep clear of the ears (y 0.44 to 0.60).
    private static let callouts = [
        Callout(id: "face", area: .face, anchor: CGPoint(x: 0.25, y: 0.35), labelY: 0.33, leading: true),
        Callout(id: "jawLeft", area: .jaw, anchor: CGPoint(x: 0.25, y: 0.79), labelY: 0.82, leading: true),
        Callout(id: "nose", area: .nose, anchor: CGPoint(x: 0.53, y: 0.38), labelY: 0.33, leading: false),
        Callout(id: "jawRight", area: .jaw, anchor: CGPoint(x: 0.75, y: 0.79), labelY: 0.82, leading: false),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let c = Self.calloutShare * w
            let m = Self.mapShare * w
            let h = m * BodyMapShapes.faceAspect
            let mapX = c - Self.overlap * m
            ZStack(alignment: .topLeading) {
                BodyMapView(side: .face, mode: .display(percentByArea: percents, showsLabels: true), width: m,
                            calloutAreas: Self.calloutAreas)
                    .offset(x: mapX)

                ForEach(Self.callouts) { callout in
                    let anchor = CGPoint(x: mapX + callout.anchor.x * m, y: callout.anchor.y * h)
                    let labelY = callout.labelY * h
                    let columnEdge = callout.leading ? c - 2 : w - c + 2
                    leader(from: CGPoint(x: columnEdge, y: labelY), to: anchor)
                    Circle()
                        .fill(DS.Color.primaryText)
                        .overlay(Circle().stroke(DS.Color.cardBackground, lineWidth: 1))
                        .frame(width: 5, height: 5)
                        .position(anchor)
                    calloutLabel(callout.area, alignment: callout.leading ? .trailing : .leading)
                        .frame(width: c - 4, alignment: callout.leading ? .trailing : .leading)
                        .position(x: callout.leading ? (c - 4) / 2 : w - c + 4 + (c - 4) / 2, y: labelY)
                }
                .accessibilityHidden(true)
            }
        }
        .aspectRatio(1 / (Self.mapShare * BodyMapShapes.faceAspect), contentMode: .fit)
        .frame(maxWidth: maxMapWidth / Self.mapShare)
    }

    private func calloutLabel(_ area: SkinTag.Area, alignment: HorizontalAlignment) -> some View {
        let value = percents[area] ?? nil
        // "Face" alone would echo the card title; the band is the whole-face tag.
        return VStack(alignment: alignment, spacing: 0) {
            Text(area == .face ? "Whole face" : area.rawValue)
                .font(.system(size: 11))
                .foregroundColor(DS.Color.secondaryText)
            Text(value.map { "\($0)%" } ?? "–")
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundColor(DS.Color.primaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func leader(from start: CGPoint, to end: CGPoint) -> some View {
        Path { p in
            p.move(to: start)
            p.addLine(to: end)
        }
        .stroke(DS.Color.secondaryText.opacity(0.6), lineWidth: 0.75)
    }
}

#Preview {
    NavigationStack {
        SkinInsightsView()
            .environmentObject(EventStore(preview: true))
            .environmentObject(ArchivedDataStore())
            .environmentObject(AppSettings())
    }
}
