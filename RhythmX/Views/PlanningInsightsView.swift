//  PlanningInsightsView.swift
//  Insights content for Planning mode: fertile window, likely ovulation, two-week wait,
//  basal temperature and ovulation test results. The cards sit under the mode switcher in InsightsView.

import SwiftUI
import Charts

struct PlanningInsightsView: View {
    static let disclaimer = "Predictions are estimates and are not birth control."

    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var fertileStore: FertileStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var healthSync: HealthSync
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var today: Date = Date()

    var body: some View {
        let insights = PlanningInsights.make(events: myEvents.cycleEvents, overrides: fertileStore.overrides, today: today,
                                             importedTemperatures: healthSync.importedTemperatures)
        let stats = InsightsViewModel(events: myEvents.cycleEvents,
                                      archivedBlocks: archivedDataStore.cycleBlocks,
                                      appSettings: appSettings).cycleStats(today: today)
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if insights.hasCycle {
                heroCard(insights, stats: stats)
            } else {
                noCycleCard
            }
            temperatureChart(insights).cardStyle()
            testsCard(insights).cardStyle()
            Text(Self.disclaimer)
                .font(DS.Font.micro)
                .foregroundColor(DS.Color.secondaryText)
                .padding(.horizontal, DS.Spacing.xs)
        }
    }

    // MARK: - Hero

    private func heroCard(_ insights: PlanningInsights, stats: InsightsViewModel.CycleStats) -> some View {
        VStack(spacing: DS.Spacing.md) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.md))
                : AnyLayout(HStackLayout(spacing: DS.Spacing.md))) {
                PhaseRingView(cycleLength: stats.averageCycleLength ?? 28, currentPhase: stats.currentPhase)
                    .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(headline(insights).caption)
                        .font(DS.Font.caption)
                        .foregroundColor(DS.Color.secondaryText)
                    Text(headline(insights).value)
                        .font(DS.Font.displayTitle.weight(.bold))
                        .minimumScaleFactor(0.7)
                        .foregroundColor(DS.Color.primaryText)
                    Text(headline(insights).detail)
                        .font(DS.Font.label.weight(.semibold))
                        .foregroundColor(levelColor(insights.fertilityLevel))
                }
                Spacer(minLength: 0)
            }
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: DS.Spacing.sm))
                : AnyLayout(HStackLayout())) {
                stat(insights.fertileWindow.map(windowText) ?? "-", "fertile window")
                stat(levelTitle(insights.fertilityLevel), "fertility")
                stat(stats.averageCycleLength.map { "\($0)d" } ?? "-", "avg cycle")
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func headline(_ insights: PlanningInsights) -> (caption: String, value: String, detail: String) {
        let ovulationDate = insights.likelyOvulation.map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
        if let wait = insights.twoWeekWaitDay {
            return ("Two-week wait", "Day \(wait) of \(PlanningInsights.twoWeekWaitLength)",
                    insights.latestTest?.result == .peak || insights.latestTest?.result == .positive
                        ? "Ovulation confirmed by your test"
                        : "Counted from your likely ovulation day")
        }
        if let days = insights.daysToOvulation {
            let value = days == 0 ? "Today" : (days == 1 ? "Tomorrow" : "In \(days) days")
            return ("Likely ovulation", value, ovulationDate.map { "\($0), \(levelTitle(insights.fertilityLevel).lowercased()) fertility" } ?? "")
        }
        if let window = insights.fertileWindow, window.lowerBound > today.startOfDay {
            let days = Calendar.current.dateComponents([.day], from: today.startOfDay, to: window.lowerBound).day ?? 0
            return ("Fertile window", days == 1 ? "Opens tomorrow" : "Opens in \(days) days", windowText(window))
        }
        return ("Likely ovulation", "Passed", ovulationDate.map { "Was \($0)" } ?? "Log your period in Cycles when it starts")
    }

    private func windowText(_ window: ClosedRange<Date>) -> String {
        let sameMonth = Calendar.current.isDate(window.lowerBound, equalTo: window.upperBound, toGranularity: .month)
        let start = window.lowerBound.formatted(.dateTime.month(.abbreviated).day())
        let end = sameMonth ? window.upperBound.formatted(.dateTime.day())
                            : window.upperBound.formatted(.dateTime.month(.abbreviated).day())
        return "\(start)–\(end)"
    }

    private func levelTitle(_ level: PlanningInsights.Level) -> String {
        switch level {
        case .low:    return "Low"
        case .rising: return "Rising"
        case .high:   return "High"
        case .peak:   return "Peak"
        }
    }

    private func levelColor(_ level: PlanningInsights.Level) -> Color {
        switch level {
        case .low:    return DS.Color.secondaryText
        case .rising: return appSettings.phaseColor(for: .follicular)
        case .high, .peak: return appSettings.phaseColor(for: .ovulation)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                .minimumScaleFactor(0.8).lineLimit(1)
            Text(label).font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty state

    private var noCycleCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                MoonPhaseView(phase: .new, color: appSettings.phaseColor(for: .ovulation), isActive: false, size: 24)
                Text("No cycle yet")
                    .font(DS.Font.sectionHeader)
                    .foregroundColor(DS.Color.primaryText)
            }
            Text("Log your period's first day with Log period in Cycles. Your fertile window, likely ovulation day and the two-week wait will appear here.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)
            Text("Then log Basal Temp and Ovulation Test tags from a day in the Calendar or from the Tags tab.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)
        }
        .cardStyle()
    }

    // MARK: - Basal temperature

    @ViewBuilder
    private func temperatureChart(_ insights: PlanningInsights) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Basal Temperature")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text(healthSync.importedTemperatures.isEmpty
                 ? "Your morning temperature by day. A sustained rise usually follows ovulation."
                 : "Your morning temperature by day, including readings from Apple Health. A sustained rise usually follows ovulation.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            let points = insights.temperatures
            if points.isEmpty {
                placeholderCard(icon: "thermometer.medium",
                    message: "Log a Basal Temp tag with the number you measured, for example 97.8, on each day in the Calendar or the Tags tab. The chart draws from those numbers.")
            } else {
                let values = points.map(\.value)
                let lower = (values.min() ?? 0) - 0.3
                let upper = (values.max() ?? 0) + 0.3
                let average = values.reduce(0, +) / Double(values.count)
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Day", point.date, unit: .day), y: .value("Temperature", point.value))
                            .foregroundStyle(DS.Color.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Day", point.date, unit: .day), y: .value("Temperature", point.value))
                            .foregroundStyle(ovulationDay(point.date, insights) ? appSettings.phaseColor(for: .ovulation) : DS.Color.accent)
                            .symbolSize(ovulationDay(point.date, insights) ? 70 : 40)
                    }
                    if points.count >= 2 {
                        RuleMark(y: .value("Average", average))
                            .foregroundStyle(DS.Color.secondaryText.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                    }
                }
                .chartYScale(domain: lower...upper)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(.caption2)
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, points.count / 5))) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.caption2)
                        AxisGridLine()
                    }
                }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : 150)
                .accessibilityLabel("Basal temperature chart")
                .accessibilityValue("\(points.count) readings, latest \(points.last.map { String(format: "%.1f", $0.value) } ?? "")")

                FlowLayout(spacing: DS.Spacing.md) {
                    HStack(spacing: DS.Spacing.xs) {
                        Circle().fill(appSettings.phaseColor(for: .ovulation)).frame(width: 8, height: 8)
                        Text("Likely ovulation day").font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                    }
                    if points.count >= 2 {
                        HStack(spacing: DS.Spacing.xs) {
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: 5))
                                path.addLine(to: CGPoint(x: 14, y: 5))
                            }
                            .stroke(DS.Color.secondaryText.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .frame(width: 14, height: 10)
                            Text("Dashed = average").font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                        }
                    }
                }
                .padding(.top, DS.Spacing.xs)
            }
        }
    }

    private func ovulationDay(_ date: Date, _ insights: PlanningInsights) -> Bool {
        guard let likely = insights.likelyOvulation else { return false }
        return Calendar.current.isDate(date, inSameDayAs: likely)
    }

    // MARK: - Ovulation tests

    @ViewBuilder
    private func testsCard(_ insights: PlanningInsights) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Ovulation Tests")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("Results read from your Planning tags.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            if insights.testResults.isEmpty {
                placeholderCard(icon: "testtube.2",
                    message: "On the day you test, log an Ovulation Test tag (Negative, Faint, Positive or Peak) from the Calendar or the Tags tab. The latest result and the two-week wait count show here.")
            } else {
                if let latest = insights.latestTest {
                    HStack(spacing: DS.Spacing.sm) {
                        Circle().fill(testColor(latest.result)).frame(width: 10, height: 10)
                        Text("Latest: \(latest.result.title)")
                            .font(DS.Font.label.weight(.semibold))
                            .foregroundColor(DS.Color.primaryText)
                        Text(latest.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(DS.Font.caption)
                            .foregroundColor(DS.Color.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
                FlowLayout(spacing: DS.Spacing.sm) {
                    ForEach(insights.testResults.suffix(8)) { point in
                        HStack(spacing: DS.Spacing.xs) {
                            Circle().fill(testColor(point.result)).frame(width: 8, height: 8)
                            Text("\(point.date.formatted(.dateTime.month(.abbreviated).day())) \(point.result.title)")
                                .font(DS.Font.micro)
                                .foregroundColor(DS.Color.secondaryText)
                        }
                        .padding(.vertical, DS.Spacing.xs)
                        .padding(.horizontal, DS.Spacing.sm)
                        .background(DS.Color.pageBackground)
                        .cornerRadius(DS.Radius.chip)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func testColor(_ result: PlanningInsights.TestResult) -> Color {
        switch result {
        case .negative: return DS.Color.tertiaryText
        case .faint:    return appSettings.phaseColor(for: .ovulation).opacity(0.5)
        case .positive: return appSettings.phaseColor(for: .ovulation)
        case .peak:     return DS.Color.accent
        }
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
        PlanningInsightsView()
            .padding()
    }
    .background(DS.Color.pageBackground)
    .environmentObject(EventStore(preview: true))
    .environmentObject(ArchivedDataStore())
    .environmentObject(FertileStore())
    .environmentObject(AppSettings())
    .environmentObject(HealthSync())
}
