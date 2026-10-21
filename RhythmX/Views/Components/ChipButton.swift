//  ChipButton.swift

import SwiftUI

struct ChipButton: View {
    let title: String
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.caption.weight(.medium))
                .foregroundColor(isSelected ? DS.Color.onAccent : DS.Color.accent)
                .padding(.vertical, DS.Spacing.sm)
                .padding(.horizontal, DS.Spacing.md)
                .background(isSelected ? DS.Color.accent : DS.Color.cardBackground)
                .cornerRadius(DS.Radius.chip)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip)
                        .stroke(DS.Color.accent.opacity(0.3), lineWidth: 1)
                )
        }
        .accessibilityLabel(title)
    }
}

#Preview {
    HStack(spacing: DS.Spacing.sm) {
        ChipButton(title: "Cramps", isSelected: true) {}
        ChipButton(title: "Fatigue") {}
        ChipButton(title: "Bloating") {}
    }
    .padding()
}
