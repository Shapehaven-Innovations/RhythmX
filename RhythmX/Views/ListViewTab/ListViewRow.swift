//  ListViewRow.swift

import SwiftUI

struct ListViewRow: View {
    let event: Event
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            MoonPhaseView(phase: event.eventType.moonPhase, color: appSettings.phaseColor(for: event.eventType), size: 22)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(event.eventType.displayName)
                    .font(DS.Font.label.weight(.semibold))
                    .foregroundColor(DS.Color.primaryText)

                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.secondaryText)

                if !event.tags.isEmpty {
                    FlowLayout(spacing: DS.Spacing.xs) {
                        ForEach(TagParser.chips(from: [event.tags])) { chip in
                            Text(chip.label)
                                .font(DS.Font.micro)
                                .padding(.vertical, 3).padding(.horizontal, DS.Spacing.sm)
                                .background(DS.Color.accent.opacity(0.12))
                                .foregroundColor(DS.Color.accent)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}
