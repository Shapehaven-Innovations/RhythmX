//  SkinTodayCard.swift
//  The Today card for skin (design 9.4, mockup 4): one sentence, a small face map for today's phase and the
//  top three flaring areas by phase, with "Log skin" and "See skin details". Shown in every mode; phase
//  elements give way to three plain tiles in Menopause. Below the two-cycle minimum the grid is hidden and
//  the face shows today's logs.

import SwiftUI

struct SkinTodayCard: View {
    let stats: SkinStats                 // window .all, kinds nil, built by TodayView from value copies
    let todayPhase: Event.EventType?     // nil in Menopause or without a cycle day
    let cycleDay: Int?
    let mode: TrackingMode
    let todaySkin: [SkinTag]             // for the face map when below minimum
    let onLog: () -> Void
    let onDetails: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let phases: [Event.EventType] = [.menstrual, .follicular, .ovulation, .luteal]
    private static let cellSize: CGFloat = 34
    private static let faceWidth: CGFloat = 100
    /// Today's logged areas are drawn at ramp bucket 3 below the minimum.
    private static let loggedTodayPercent = 30

    private var isMenopause: Bool { mode == .menopause }
    private var sentence: String { stats.sentence(todayPhase: todayPhase, cycleDay: cycleDay, mode: mode) }

    /// Phase data is shown once two cycles are covered; Menopause shows tiles once a few days are logged.
    private var showsData: Bool {
        isMenopause ? stats.loggedDays >= SkinStats.minimumDaysForBody : stats.hasPhaseData
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                header
                sentenceText
            }
            .accessibilityElement(children: .combine)
            .accessibilitySortPriority(2)

            graphs
                .padding(.top, DS.Spacing.xs)
                .accessibilitySortPriority(1)

            buttons
                .padding(.top, DS.Spacing.sm)
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header and sentence

    private var detailsTitle: String {
        if isMenopause { return "All time ›" }
        switch stats.cyclesCovered {
        case 0:  return "Details ›"
        case 1:  return "Last cycle ›"
        default: return "Last \(stats.cyclesCovered) cycles ›"
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Skin")
                .font(.title3.weight(.semibold))
                .foregroundColor(DS.Color.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Spacing.sm)
            Button(detailsTitle, action: onDetails)
                .font(DS.Font.label)
                .foregroundColor(DS.Color.secondaryText)
                .frame(minHeight: 44)
                .accessibilityLabel("See skin details")
        }
        .frame(minHeight: 44)
    }

    /// The phase word in "the {phase} phase" in its fixed phase colour and bold, as `TodayView.moodLine` styles.
    private var sentenceText: some View {
        let line = sentence
        var text = AttributedString(line)
        text.foregroundColor = DS.Color.primaryText
        for phase in Self.phases {
            if let range = text.range(of: "the \(phase.rawValue) phase"),
               let word = text[range].range(of: phase.rawValue) {
                text[word].foregroundColor = phase.phaseColor
                text[word].font = .body.weight(.bold)
            }
        }
        return Text(text)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Face and grid

    /// The face for today's phase; all phases when there is none or that phase has too few days.
    private var facePhase: Event.EventType? {
        guard !isMenopause, let todayPhase else { return nil }
        let days = stats.loggedDaysByPhase[todayPhase] ?? 0
        return days >= SkinStats.minimumDaysPerPhase ? todayPhase : nil
    }

    private var facePercents: [SkinTag.Area: Int?] {
        if showsData { return stats.percentByArea(phase: facePhase) }
        var map: [SkinTag.Area: Int?] = [:]
        for tag in todaySkin where tag.isFlare { map[tag.area] = .some(Self.loggedTodayPercent) }
        return map
    }

    private var faceCaption: String {
        if !showsData { return todaySkin.isEmpty ? "Today · face" : "Logged today · face" }
        return "\(facePhase?.rawValue.capitalized ?? "All days") · face"
    }

    private var face: some View {
        VStack(spacing: DS.Spacing.xs) {
            BodyMapView(side: .face, mode: .display(percentByArea: facePercents, showsLabels: false),
                        width: Self.faceWidth)
            Text(faceCaption)
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(true)
        }
        .frame(width: Self.faceWidth)
    }

    @ViewBuilder
    private var graphs: some View {
        let rows = showsData ? stats.topAreas(limit: 3) : []
        if rows.isEmpty {
            face.frame(maxWidth: .infinity)
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                face.frame(maxWidth: .infinity)
                if isMenopause { tiles(rows) } else { grid(rows) }
            }
        } else {
            HStack(alignment: .center, spacing: DS.Spacing.md) {
                face
                if isMenopause { tiles(rows) } else { grid(rows) }
            }
        }
    }

    private var labelWidth: CGFloat? { dynamicTypeSize.isAccessibilitySize ? nil : 72 }

    private func grid(_ rows: [SkinStats.AreaRow]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // Phase pills above the columns.
            HStack(spacing: DS.Spacing.xs) {
                if let labelWidth { Color.clear.frame(width: labelWidth, height: 1) }
                ForEach(Self.phases) { phase in
                    Capsule()
                        .fill(phase.phaseColor)
                        .frame(height: 5)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            ForEach(rows) { row in
                gridRow(row)
            }

            HStack(spacing: DS.Spacing.xs) {
                if let labelWidth { Color.clear.frame(width: labelWidth, height: 1) }
                ForEach(Self.phases) { phase in
                    Text(String(phase.rawValue.prefix(3)).capitalized)
                        .font(DS.Font.micro)
                        .foregroundColor(DS.Color.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func gridRow(_ row: SkinStats.AreaRow) -> some View {
        let label = Text(row.area.rawValue)
            .font(DS.Font.label)
            .foregroundColor(DS.Color.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        let cells = HStack(spacing: DS.Spacing.xs) {
            ForEach(row.cells, id: \.phase) { cell in
                cellView(percent: cell.percent, isPeak: cell.percent != nil && row.peak.contains(cell.phase), showsSign: false)
            }
        }
        Group {
            if let labelWidth {
                HStack(spacing: DS.Spacing.xs) {
                    label.frame(width: labelWidth, alignment: .leading)
                    cells
                }
            } else {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    label
                    cells
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SkinPhaseGridView.rowAccessibilityLabel(row))
    }

    private func cellView(percent: Int?, isPeak: Bool, showsSign: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
        return shape
            .fill(SkinRamp.fillColour(percent: percent))
            .frame(maxWidth: .infinity)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 44 : Self.cellSize)
            .overlay {
                Group {
                    if let percent {
                        Text(showsSign ? "\(percent)%" : "\(percent)")
                            .foregroundColor(SkinRamp.textColor(percent: percent))
                    } else {
                        Text("–").foregroundColor(DS.Color.secondaryText)
                    }
                }
                .font(DS.Font.label.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
            }
            .overlay {
                if isPeak { shape.stroke(DS.Color.primaryText, lineWidth: 2) }
            }
    }

    /// Menopause: the top three areas as tiles with their share of all logged days.
    private func tiles(_ rows: [SkinStats.AreaRow]) -> some View {
        let percents = stats.percentByArea(phase: nil)
        return VStack(spacing: DS.Spacing.xs) {
            ForEach(rows) { row in
                let percent = percents[row.area] ?? nil
                HStack(spacing: DS.Spacing.sm) {
                    Text(row.area.rawValue)
                        .font(DS.Font.label)
                        .foregroundColor(DS.Color.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    cellView(percent: percent, isPeak: false, showsSign: true)
                        .frame(width: 64)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.area.rawValue)
                .accessibilityValue(percent.map { "\($0) percent of logged days" } ?? "not enough days")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: DS.Spacing.sm) {
                SecondaryButton(title: "Log skin", action: onLog)
                PrimaryButton(title: "See skin details", action: onDetails)
            }
        } else {
            HStack(spacing: DS.Spacing.sm) {
                SecondaryButton(title: "Log skin", action: onLog)
                PrimaryButton(title: "See skin details", action: onDetails)
            }
        }
    }
}
