//  InsightsHeroCard.swift

import SwiftUI

struct InsightsHeroCard: View {
    let stats: InsightsViewModel.CycleStats
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.md))
                : AnyLayout(HStackLayout(spacing: DS.Spacing.md))) {
                PhaseRingView(cycleLength: stats.averageCycleLength ?? 28, currentPhase: stats.currentPhase)
                    .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Today")
                        .font(DS.Font.caption)
                        .foregroundColor(DS.Color.secondaryText)
                    Text(stats.currentCycleDay.map { "Day \($0)" } ?? "No active cycle")
                        .font(DS.Font.displayTitle.weight(.bold))
                        .minimumScaleFactor(0.7)
                        .foregroundColor(DS.Color.primaryText)
                    if let phase = stats.currentPhase {
                        Text(phase.displayName)
                            .font(DS.Font.label.weight(.semibold))
                            .foregroundColor(appSettings.phaseColor(for: phase))
                    }
                }
                Spacer(minLength: 0)
            }
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: DS.Spacing.sm))
                : AnyLayout(HStackLayout())) {
                stat(stats.averageCycleLength.map { "\($0)d" } ?? "-", "avg cycle")
                stat(stats.averagePeriodLength.map { "\($0)d" } ?? "-", "avg period")
                stat(stats.nextPeriodEstimate.map { $0.startOfDay < Date().startOfDay ? "Overdue" : $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "-", "next period")
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            Text(label).font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}
