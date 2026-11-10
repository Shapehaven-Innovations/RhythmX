//  SkinPhaseGridView.swift
//
//  The box graph: body areas by cycle phase, each cell the share of logged days in that phase with the chosen
//  skin type on that area, filled from `SkinRamp`. Layout follows `TagPatternsView.heatmapCard`; phase colours
//  appear only in the column pills, never as a cell fill.

import SwiftUI

struct SkinPhaseGridView: View {
    let events: [Event]
    let archivedBlocks: [ArchivedDataBlock]
    let today: Date
    let window: SkinStats.Window

    @State private var filter: SkinStats.KindFilter = .acneBreakout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(events: [Event], archivedBlocks: [ArchivedDataBlock], today: Date = Date(), window: SkinStats.Window) {
        self.events = events
        self.archivedBlocks = archivedBlocks
        self.today = today
        self.window = window
    }

    private static let phases: [Event.EventType] = [.menstrual, .follicular, .ovulation, .luteal]
    /// One representative percent per ramp bucket 1...5, for the legend.
    private static let legendPercents = [5, 15, 30, 45, 60]

    var body: some View {
        let stats = SkinStats(events: events, archivedBlocks: archivedBlocks, today: today,
                              window: window, kinds: filter.kinds)
        let rows = stats.rows()
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                filterChips

                if !stats.hasPhaseData {
                    placeholderCard(icon: "square.grid.3x3",
                                    message: "Log your skin through two cycles to see it by phase. \(min(stats.cyclesCovered, SkinStats.minimumCycles)) of \(SkinStats.minimumCycles) so far.")
                        .cardStyle()
                } else {
                    if let first = rows.first, let headline = stats.headline(area: first.area, filter: filter) {
                        headlineCard(headline)
                    }
                    gridCard(stats: stats, rows: rows)
                }
            }
            .padding(DS.Spacing.md)
        }
        .themedPage()
        .navigationTitle("By phase")
        .navigationBarTitleDisplayMode(.large)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(SkinStats.KindFilter.allCases) { option in
                    let selected = option == filter
                    Button {
                        filter = option
                    } label: {
                        Text(option.rawValue)
                            .font(DS.Font.label.weight(selected ? .semibold : .regular))
                            .foregroundColor(selected ? DS.Color.primaryText : DS.Color.secondaryText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, DS.Spacing.md)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(selected ? DS.Color.accent.opacity(0.22) : DS.Color.pageBackground))
                            .overlay(Capsule().stroke(selected ? DS.Color.accent : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.rawValue)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Skin type")
    }

    private func dayCount(_ days: Int) -> String { "\(days) \(days == 1 ? "day" : "days")" }

    private var typesPhrase: String {
        filter.rawValue.lowercased().replacingOccurrences(of: " & ", with: " or ")
    }

    // MARK: - Headline

    private func headlineCard(_ headline: (title: String, detail: String)) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            Image(systemName: "exclamationmark.circle")
                .font(.title3.weight(.semibold))
                .foregroundColor(DS.Color.accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(DS.Color.accent.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline.title)
                    .font(DS.Font.sectionHeader)
                    .foregroundColor(DS.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(headline.detail)
                    .font(DS.Font.label)
                    .foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Grid

    private func gridCard(stats: SkinStats, rows: [SkinStats.AreaRow]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if rows.isEmpty {
                placeholderCard(icon: "square.grid.3x3",
                                message: "No \(typesPhrase) logged on any area in this window yet.")
            } else {
                VStack(spacing: DS.Spacing.xs) {
                    header(stats: stats)
                    ForEach(rows) { row in
                        gridRow(row)
                    }
                }
            }
            legend
            Text("% of days in that phase with \(typesPhrase) logged on that area. Outlined = the phase where it peaks.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var labelWidth: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? nil : 104
    }

    private func cyclesCaption(_ stats: SkinStats) -> String {
        stats.cyclesCovered == 1 ? "Last cycle" : "Last \(stats.cyclesCovered) cycles"
    }

    @ViewBuilder
    private func header(stats: SkinStats) -> some View {
        let caption = Text(cyclesCaption(stats))
            .font(DS.Font.micro)
            .foregroundColor(DS.Color.secondaryText)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                caption
                ForEach(Self.phases) { phase in
                    let days = stats.loggedDaysByPhase[phase] ?? 0
                    HStack(spacing: DS.Spacing.sm) {
                        Capsule().fill(phase.phaseColor).frame(width: 24, height: 6)
                        Text("\(phase.rawValue.capitalized), \(dayCount(days))")
                            .font(DS.Font.label)
                            .foregroundColor(DS.Color.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(phase.rawValue.capitalized)
                    .accessibilityValue("\(dayCount(days)) logged")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let columns = HStack(alignment: .top, spacing: DS.Spacing.xs) {
                ForEach(Self.phases) { phase in
                    let days = stats.loggedDaysByPhase[phase] ?? 0
                    VStack(spacing: 2) {
                        Capsule()
                            .fill(phase.phaseColor)
                            .frame(height: 6)
                        Text(phase.rawValue.capitalized)
                            .font(DS.Font.micro.weight(.semibold))
                            .foregroundColor(DS.Color.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(dayCount(days))
                            .font(DS.Font.micro)
                            .foregroundColor(DS.Color.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(phase.rawValue.capitalized)
                    .accessibilityValue("\(dayCount(days)) logged")
                }
            }
            HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
                caption.frame(width: labelWidth, alignment: .leading)
                columns
            }
        }
    }

    private func gridRow(_ row: SkinStats.AreaRow) -> some View {
        let label = Text(row.area.rawValue)
            .font(DS.Font.label)
            .foregroundColor(DS.Color.primaryText)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(0.85)
        let cells = HStack(spacing: DS.Spacing.xs) {
            ForEach(row.cells, id: \.phase) { cell in
                cellView(cell, isPeak: cell.percent != nil && row.peak.contains(cell.phase))
            }
        }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    label
                    cells
                }
                .padding(.vertical, DS.Spacing.xs)
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    label.frame(width: labelWidth, alignment: .leading)
                    cells
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.rowAccessibilityLabel(row))
    }

    private func cellView(_ cell: SkinStats.PhaseCell, isPeak: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
        return shape
            .fill(SkinRamp.fillColour(percent: cell.percent))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .overlay {
                Group {
                    if let percent = cell.percent {
                        Text("\(percent)%")
                            .foregroundColor(SkinRamp.textColor(percent: percent))
                    } else {
                        Text("–")
                            .foregroundColor(DS.Color.secondaryText)
                    }
                }
                .font(DS.Font.label.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
            }
            .overlay {
                if isPeak {
                    shape.stroke(DS.Color.primaryText, lineWidth: 2)
                }
            }
    }

    static func rowAccessibilityLabel(_ row: SkinStats.AreaRow) -> String {
        let parts = row.cells.map { cell -> String in
            if let percent = cell.percent { return "\(percent) percent in \(cell.phase.rawValue)" }
            return "not enough days in \(cell.phase.rawValue)"
        }
        var label = "\(row.area.rawValue): " + parts.joined(separator: ", ")
        let peaks = phases.filter(row.peak.contains).map(\.rawValue)
        if !peaks.isEmpty { label += ", peak in " + peaks.joined(separator: " and ") }
        return label
    }

    // MARK: - Legend

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
        .padding(.top, DS.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Colour scale from 0 percent, lightest, to 50 percent or more, darkest")
    }

    // MARK: - Placeholder

    private func placeholderCard(icon: String, message: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: icon).foregroundColor(DS.Color.secondaryText).frame(width: DS.Spacing.lg)
                .accessibilityHidden(true)
            Text(message).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.pageBackground)
        .cornerRadius(DS.Radius.chip)
    }
}

#Preview {
    NavigationStack {
        SkinPhaseGridView(events: EventStore(preview: true).events, archivedBlocks: [], window: .ninety)
    }
}
