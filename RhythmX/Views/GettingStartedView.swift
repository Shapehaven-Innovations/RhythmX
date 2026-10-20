//  GettingStartedView.swift

import SwiftUI

struct GettingStartedView: View {
    private let steps: [(String, String)] = [
        ("Pick a mode",
         "At the top of Insights, choose Cycle, Planning, or Menopause. Your history is shared across all three."),
        ("Start a cycle",
         "In Cycles, choose the first day and length, then tap Generate cycle."),
        ("Add tags",
         "In Tags, or from a day on the Calendar, tap + to log symptoms, mood, and more."),
        ("Check the calendar",
         "See your phases at a glance. Tap any day to view its tags."),
        ("Archive a cycle",
         "When a cycle ends, archive it from Cycles, then review it in Past Cycles."),
        ("Back up your data",
         "In Settings, save a backup file to Files. Restore it later on this or another iPhone."),
        ("Learn more",
         "In Cycles, open Learn about phases for details on each phase.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(DS.Color.onAccent)
                            .frame(width: 22, height: 22)
                            .background(DS.Color.accent)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.0)
                                .font(DS.Font.label.weight(.semibold))
                                .foregroundColor(DS.Color.primaryText)
                            Text(step.1)
                                .font(DS.Font.caption)
                                .foregroundColor(DS.Color.secondaryText)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.cardBackground)
                    .cornerRadius(DS.Radius.card)
                }
            }
            .padding(DS.Spacing.md)
        }
        .themedPage()
        .navigationTitle("How RhythmX works")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        GettingStartedView()
    }
}
