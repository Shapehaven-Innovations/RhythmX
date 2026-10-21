//  TagDetailView.swift
//  One tag from the Patterns heatmap: how often it appeared on each cycle day across the last 6
//  cycles (phase bands behind, labelled by moon), a count per phase, and the finding sentence.
//  In Menopause the chart is the tag's count per week instead, since there is no cycle.

import SwiftUI
import Charts

struct TagDetailView: View {
    let row: TagPhaseRow
    let mode: TrackingMode
    var today: Date = Date()

    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Charts keep the user's text size; at accessibility sizes they get more room so labels do not clip.
    private var chartHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 230 : 160 }

    private struct WeekBar: Identifiable {
        let id: Int
        let label: String
        let count: Int
    }

    private var isWeekly: Bool { mode == .menopause }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if isWeekly {
                    weekChartCard
                } else {
                    cycleChartCard
                }
                countsCard
                sentenceCard
                Text(TagPatternsView.disclaimer)
                    .font(DS.Font.micro)
                    .foregroundColor(DS.Color.secondaryText)
                    .padding(.horizontal, DS.Spacing.xs)
            }
            .padding(DS.Spacing.md)
        }
        .themedPage()
        .navigationTitle(row.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Cycle day chart

    @ViewBuilder
    private var cycleChartCard: some View {
        let counts = PatternFinder.cycleDayCounts(tag: row.tag, events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks)
        let bands = PatternFinder.phaseBands(events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks)
        let maxDay = max(bands.map(\.endDay).max() ?? 0, counts.map(\.cycleDay).max() ?? 0, 1)

        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("By Cycle Day")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("How many times \(row.label) was logged on each cycle day across your last \(PatternFinder.maxCycles) cycles. The bands behind are your phases.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            if counts.isEmpty {
                Text("No entries in the cycles considered.")
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.secondaryText)
            } else {
                Chart {
                    ForEach(bands) { band in
                        RectangleMark(
                            xStart: .value("Start", Double(band.startDay) - 0.5),
                            xEnd: .value("End", Double(band.endDay) + 0.5)
                        )
                        .foregroundStyle(appSettings.phaseColor(for: band.phase).opacity(0.16))
                        .annotation(position: .top, alignment: .center, spacing: 2) {
                            MoonPhaseView(phase: band.phase.moonPhase, color: appSettings.phaseColor(for: band.phase), size: 12)
                        }
                    }
                    ForEach(counts) { item in
                        BarMark(
                            x: .value("Day", Double(item.cycleDay)),
                            y: .value("Times", item.count),
                            width: .fixed(6)
                        )
                        .foregroundStyle(item.phase.map { appSettings.phaseColor(for: $0) } ?? DS.Color.accent)
                        .cornerRadius(2)
                    }
                }
                .chartXScale(domain: 0.5...(Double(maxDay) + 0.5))
                .chartXAxis {
                    AxisMarks(values: .stride(by: maxDay > 20 ? 5 : 2)) { value in
                        if let v = value.as(Double.self), v >= 1 {
                            AxisValueLabel { Text("\(Int(v))").font(.caption2) }
                        }
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(.caption2)
                        AxisGridLine()
                    }
                }
                .frame(height: chartHeight + 10)
                .accessibilityLabel("\(row.label) by cycle day")
                .accessibilityValue(cycleAccessibilityValue(counts))

                HStack(spacing: DS.Spacing.md) {
                    ForEach(bands) { band in
                        HStack(spacing: DS.Spacing.xs) {
                            MoonPhaseView(phase: band.phase.moonPhase, color: appSettings.phaseColor(for: band.phase), size: 12)
                            Text(band.phase.rawValue.capitalized)
                                .font(DS.Font.micro)
                                .foregroundColor(DS.Color.secondaryText)
                        }
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .cardStyle()
    }

    private func cycleAccessibilityValue(_ counts: [TagCycleDayCount]) -> String {
        counts.map { "day \($0.cycleDay): \($0.count)" }.joined(separator: ", ")
    }

    // MARK: - Week chart (Menopause)

    @ViewBuilder
    private var weekChartCard: some View {
        let bars = row.cells.enumerated().map { index, cell in
            WeekBar(id: index, label: weekLabel(index), count: cell.count)
        }
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("By Week")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("How many times \(row.label) was logged in each of the last \(PatternFinder.weeks) weeks. Oldest week on the left.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            Chart(bars) { bar in
                BarMark(x: .value("Week", bar.label), y: .value("Times", bar.count))
                    .foregroundStyle(bar.id == bars.count - 1 ? DS.Color.accent : DS.Color.accent.opacity(0.55))
                    .cornerRadius(3)
                    .annotation(position: .top) {
                        if bar.count > 0 {
                            Text("\(bar.count)").font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                        }
                    }
            }
            .chartXScale(domain: bars.map(\.label))
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption2) }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().font(.caption2)
                    AxisGridLine()
                }
            }
            .frame(height: chartHeight)
            .accessibilityLabel("\(row.label) by week")
            .accessibilityValue(bars.map { "\($0.label): \($0.count)" }.joined(separator: ", "))
        }
        .cardStyle()
    }

    private func weekLabel(_ index: Int) -> String {
        let weeksAgo = PatternFinder.weeks - 1 - index
        return weeksAgo == 0 ? "Now" : "\(weeksAgo)w"
    }

    // MARK: - Counts

    private var countsCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(isWeekly ? "Count per Week" : "Count per Phase")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            VStack(spacing: 0) {
                ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                    HStack(spacing: DS.Spacing.sm) {
                        if let phase = cell.phase {
                            MoonPhaseView(phase: phase.moonPhase, color: appSettings.phaseColor(for: phase), size: 18)
                            Text(phase.displayName).font(DS.Font.label).foregroundColor(DS.Color.primaryText)
                        } else {
                            Text(weekTitle(index)).font(DS.Font.label).foregroundColor(DS.Color.primaryText)
                        }
                        Spacer()
                        Text(cell.count == 1 ? "1 time" : "\(cell.count) times")
                            .font(DS.Font.caption)
                            .foregroundColor(DS.Color.secondaryText)
                    }
                    .padding(.vertical, DS.Spacing.sm)
                    .accessibilityElement(children: .combine)
                    if index != row.cells.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .cardStyle()
    }

    private func weekTitle(_ index: Int) -> String {
        let weeksAgo = PatternFinder.weeks - 1 - index
        switch weeksAgo {
        case 0: return "This week"
        case 1: return "1 week ago"
        default: return "\(weeksAgo) weeks ago"
        }
    }

    // MARK: - Sentence

    @ViewBuilder
    private var sentenceCard: some View {
        let finding = PatternFinder.finding(for: row.tag, events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks,
                                            mode: mode, today: today)
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Pattern")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            if let finding {
                Text(finding.sentence).font(DS.Font.label).foregroundColor(DS.Color.primaryText)
                Text(finding.evidence).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
            } else {
                Text(isWeekly
                     ? "Not enough weeks yet to call this a pattern. A pattern needs \(row.label) in at least \(PatternFinder.minimumCycles) of the last \(PatternFinder.weeks) weeks."
                     : "Not enough cycles yet to call this a pattern. A pattern needs \(row.label) at the same point in at least \(PatternFinder.minimumCycles) cycles.")
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.secondaryText)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        TagDetailView(
            row: TagPhaseRow(tag: "Symptom:Cramps", cells: Event.EventType.allCases.map {
                TagPhaseCell(phase: $0, weekIndex: nil, count: $0 == .menstrual ? 9 : 1)
            }),
            mode: .cycle
        )
    }
    .environmentObject(EventStore(preview: true))
    .environmentObject(ArchivedDataStore())
    .environmentObject(AppSettings())
}
