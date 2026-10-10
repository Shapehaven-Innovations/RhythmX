//  TodayCard.swift

import SwiftUI

struct TodayCard: View {
    let stats: InsightsViewModel.CycleStats
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var daysUntilNext: Int? {
        guard let next = stats.nextPeriodEstimate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date().startOfDay, to: next.startOfDay).day
    }

    var body: some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: DS.Spacing.md))) {
            MoonPhaseView(
                phase: (stats.currentPhase ?? .ovulation).moonPhase,
                color: stats.currentPhase.map { appSettings.phaseColor(for: $0) } ?? DS.Color.tertiaryText,
                isActive: stats.currentPhase != nil,
                size: 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.currentCycleDay.map { "Today · Day \($0)" } ?? "No active cycle")
                    .font(DS.Font.label.weight(.semibold))
                    .foregroundColor(DS.Color.primaryText)
                if let phase = stats.currentPhase {
                    Text(phase.displayName).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                }
                if let d = daysUntilNext, d >= 0 {
                    Text(d == 0 ? "Next period expected today" : "Next period in \(d) day\(d == 1 ? "" : "s")")
                        .font(DS.Font.caption)
                        .foregroundColor(appSettings.phaseColor(for: .menstrual))
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
