//  PrimaryButton.swift

import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.label.weight(.semibold))
                .foregroundColor(DS.Color.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isDisabled ? DS.Color.accent.opacity(0.4) : DS.Color.accent)
                .cornerRadius(DS.Radius.button)
        }
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

#Preview {
    VStack(spacing: DS.Spacing.md) {
        PrimaryButton(title: "Get Started") {}
        PrimaryButton(title: "Disabled", action: {}, isDisabled: true)
    }
    .padding()
}
