//  MenopauseInsightsView.swift
//  Insights content for Menopause mode: the count toward 12 months without a period, hot flashes per
//  week, this week's tags and, from Apple Health, the last 7 nights of sleep. No next-period prediction and
//  no phase ring, since there is no cycle.

import SwiftUI
import Charts

struct MenopauseInsightsView: View {
    static let disclaimer = "Tracking tool, not medical advice."

    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var healthSync: HealthSync
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var today: Date = Date()

    private struct WeekBar: Identifiable {
        let id: Int
        let label: String
        let count: Int
    }

    var body: some View {
        let insights = MenopauseInsights.make(events: myEvents.events, today: today)
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if insights.hasData {
                monthsCard(insights)
                hotFlashesChart(insights).cardStyle()
                weekCard(insights).cardStyle()
            } else {
                emptyCard
            }
            sleepCard.cardStyle()
            Text(Self.disclaimer)
                .font(DS.Font.micro)
                .foregroundColor(DS.Color.secondaryText)
                .padding(.horizontal, DS.Spacing.xs)
        }
    }

    // MARK: - Months since last period

    private func monthsCard(_ insights: MenopauseInsights) -> some View {
        let months = insights.monthsSinceLastPeriod
        let goal = MenopauseInsights.monthsGoal
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Months Since Last Period")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.sm))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DS.Spacing.md))) {
                Text(insights.lastPeriod == nil ? "-" : "\(min(months, goal))")
                    .font(DS.Font.displayTitle.weight(.bold))
                    .foregroundColor(DS.Color.primaryText)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("of \(goal). After \(goal) months in a row without a period, menopause is generally considered reached.")
                        .font(DS.Font.caption)
                        .foregroundColor(DS.Color.secondaryText)
                    if let last = insights.lastPeriod {
                        Text("Last period: \(last.formatted(.dateTime.month(.abbreviated).day().year()))")
                            .font(DS.Font.caption)
                            .foregroundColor(DS.Color.secondaryText)
                    } else {
                        Text("No period logged yet. Logging a period day in the Calendar starts the count; a later period resets it.")
                            .font(DS.Font.caption)
                            .foregroundColor(DS.Color.secondaryText)
                    }
                }
            }
            HStack(spacing: 3) {
                ForEach(0..<goal, id: \.self) { i in
                    Capsule()
                        .fill(i < months ? appSettings.phaseColor(for: .luteal) : Color(UIColor.tertiarySystemFill))
                        .frame(height: 8)
                }
            }
            .accessibilityHidden(true)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(insights.lastPeriod == nil
            ? "No period logged yet"
            : "\(months) of \(goal) months since your last period")
    }

    // MARK: - Hot flashes per week

    @ViewBuilder
    private func hotFlashesChart(_ insights: MenopauseInsights) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Hot Flashes per Week")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("Every Hot Flashes tag counts. Oldest week on the left.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            let counts = insights.hotFlashesPerWeek
            if !counts.contains(where: { $0 > 0 }) {
                placeholderCard(icon: "flame",
                    message: "Tap Hot Flashes in the tag form each time one happens, from the Calendar or the Tags tab. Each tap counts and the weekly totals show here.")
            } else {
                let bars = counts.enumerated().map { index, count in
                    WeekBar(id: index, label: weekLabel(index, total: counts.count), count: count)
                }
                Chart(bars) { bar in
                    BarMark(x: .value("Week", bar.label), y: .value("Hot flashes", bar.count))
                        .foregroundStyle(bar.id == counts.count - 1
                            ? appSettings.phaseColor(for: .menstrual)
                            : appSettings.phaseColor(for: .menstrual).opacity(0.55))
                        .cornerRadius(3)
                        .annotation(position: .top) {
                            if bar.count > 0 {
                                Text("\(bar.count)").font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                            }
                        }
                }
                .chartXScale(domain: bars.map(\.label))
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(.caption2)
                        AxisGridLine()
                    }
                }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : 150)
                .accessibilityLabel("Hot flashes per week chart")
                .accessibilityValue(trendText(counts))

                Text(trendText(counts))
                    .font(DS.Font.micro)
                    .foregroundColor(DS.Color.secondaryText)
            }
        }
    }

    private func weekLabel(_ index: Int, total: Int) -> String {
        let weeksAgo = total - 1 - index
        return weeksAgo == 0 ? "Now" : "\(weeksAgo)w"
    }

    private func trendText(_ counts: [Int]) -> String {
        guard let first = counts.first(where: { $0 > 0 }), let last = counts.last else { return "" }
        let firstIndex = counts.firstIndex(where: { $0 > 0 }) ?? 0
        let span = counts.count - firstIndex
        guard span > 1 else { return "\(last) this week." }
        if last < first { return "Down from \(first) to \(last) over \(span) weeks." }
        if last > first { return "Up from \(first) to \(last) over \(span) weeks." }
        return "Steady at about \(last) a week over \(span) weeks."
    }

    // MARK: - This week

    @ViewBuilder
    private func weekCard(_ insights: MenopauseInsights) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("This Week")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("Menopause and mood tags from the last 7 days.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            let rows = insights.weekRows
            if rows.isEmpty {
                placeholderCard(icon: "tag",
                    message: "Log Menopause tags such as Night Sweats or Poor Sleep, and Mood tags, from the Calendar or the Tags tab. This week's counts show here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.label).font(DS.Font.label).foregroundColor(DS.Color.primaryText)
                            Spacer()
                            Text(row.count == 1 ? "1 time" : "\(row.count) times")
                                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                        }
                        .padding(.vertical, DS.Spacing.sm)
                        .accessibilityElement(children: .combine)
                        if row.id != rows.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sleep (Apple Health)

    /// Built only from the summary HealthSync already imported, and only while "Read sleep" is on. The card
    /// never asks Health for permission; that happens in Settings.
    @ViewBuilder
    private var sleepCard: some View {
        let readOn = appSettings.healthReadSleep
        let sleep = SleepInsights.make(summary: readOn ? healthSync.importedSleep : [:], today: today)
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Sleep")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            if readOn, sleep.hasData, let average = sleep.averageHours {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.xs))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DS.Spacing.sm))) {
                    Text(SleepInsights.hoursText(average))
                        .font(DS.Font.displayTitle.weight(.bold))
                        .foregroundColor(DS.Color.primaryText)
                    Text("average asleep over the last \(SleepInsights.nightCount) nights, from Apple Health.")
                        .font(DS.Font.caption)
                        .foregroundColor(DS.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityHidden(true)

                Chart(sleep.nights) { night in
                    BarMark(x: .value("Night", night.date, unit: .day),
                            y: .value("Hours asleep", night.hours ?? 0))
                        .foregroundStyle(night.id == sleep.nights.last?.id
                            ? appSettings.phaseColor(for: .luteal)
                            : appSettings.phaseColor(for: .luteal).opacity(0.55))
                        .cornerRadius(3)
                        .annotation(position: .top) {
                            if let hours = night.hours {
                                Text(SleepInsights.rounded(hours)).font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                            }
                        }
                }
                .chartXAxis {
                    AxisMarks(values: sleep.nights.map(\.date)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(.caption2)
                        AxisGridLine()
                    }
                }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : 150)
                .animation(reduceMotion ? nil : .easeInOut, value: sleep)
                .accessibilityElement()
                .accessibilityLabel("Sleep, last \(SleepInsights.nightCount) nights")
                .accessibilityValue(sleep.accessibilitySummary)

                Text("Hours asleep each night, oldest on the left. Sleep is not added to your events.")
                    .font(DS.Font.micro)
                    .foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                placeholderCard(icon: "bed.double", message: SleepInsights.emptyMessage(readSleepOn: readOn))
                    .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Empty state

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                MoonPhaseView(phase: .full, color: DS.Color.moon, isActive: false, size: 24)
                Text("Nothing logged yet")
                    .font(DS.Font.sectionHeader)
                    .foregroundColor(DS.Color.primaryText)
            }
            Text("Open a day in the Calendar or the Tags tab, tap Add tag and pick Hot Flashes, Night Sweats or Poor Sleep. Tap Hot Flashes once for each one.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)
            Text("The count toward 12 months without a period, hot flashes per week and this week's tags will appear here.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)
        }
        .cardStyle()
    }

    // MARK: - Placeholder

    private func placeholderCard(icon: String, message: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: icon).foregroundColor(DS.Color.secondaryText).frame(width: DS.Spacing.lg)
            Text(message).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.pageBackground)
        .cornerRadius(DS.Radius.chip)
    }
}

#Preview {
    ScrollView {
        MenopauseInsightsView()
            .padding()
    }
    .background(DS.Color.pageBackground)
    .environmentObject(EventStore(preview: true))
    .environmentObject(AppSettings())
    .environmentObject(HealthSync())
}
