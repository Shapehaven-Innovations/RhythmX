//  PredictionBannerView.swift

import SwiftUI

struct PredictionBannerView: View {
    let daysUntil: Int
    @EnvironmentObject var appSettings: AppSettings

    private var message: String {
        switch daysUntil {
        case 0:  return "Cycle anticipated to start today."
        case 1:  return "Cycle anticipated to start tomorrow."
        default: return "Cycle anticipated to start in \(daysUntil) days."
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(appSettings.phaseColor(for: .menstrual))
                .frame(width: 4)

            Image(systemName: "calendar.badge.clock")
                .foregroundColor(appSettings.phaseColor(for: .menstrual))

            Text(message)
                .font(DS.Font.label)
                .foregroundColor(DS.Color.primaryText)

            Spacer()
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.cardBackground)
        .cornerRadius(DS.Radius.card)
    }
}

#Preview {
    VStack {
        PredictionBannerView(daysUntil: 0)
        PredictionBannerView(daysUntil: 1)
        PredictionBannerView(daysUntil: 3)
    }
    .padding()
    .environmentObject(AppSettings())
}
