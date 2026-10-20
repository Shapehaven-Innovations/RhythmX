//  SecondaryButton.swift

import SwiftUI

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.label.weight(.semibold))
                .foregroundColor(isDisabled ? DS.Color.accent.opacity(0.4) : DS.Color.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.clear)
                .cornerRadius(DS.Radius.button)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.button)
                        .stroke(isDisabled ? DS.Color.accent.opacity(0.4) : DS.Color.accent, lineWidth: 1.5)
                )
        }
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

#Preview {
    VStack(spacing: DS.Spacing.md) {
        SecondaryButton(title: "Skip") {}
        SecondaryButton(title: "Disabled", action: {}, isDisabled: true)
    }
    .padding()
}
