//  LegalLinks.swift
//
//  The Terms of Use and Privacy Policy links shown next to every subscription purchase button (paywall
//  only; Settings does not carry them). Terms is Apple's standard EULA; Privacy is the Shape Haven Innovations policy. App Store
//  Connect carries the same two URLs (Privacy Policy URL field; EULA left on the standard Apple EULA).

import SwiftUI

enum LegalLinks {
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicy = URL(string: "https://shapehaveninnovations.com/privacy.html")!

    static let termsLabel = "Terms of Use (EULA)"
    static let privacyLabel = "Privacy Policy"
}

/// Both links side by side, stacked at accessibility text sizes. Each opens in Safari through `Link`.
struct LegalLinksRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var font: Font = DS.Font.caption
    var alignment: HorizontalAlignment = .center

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: alignment, spacing: DS.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: DS.Spacing.md))
        layout {
            link(LegalLinks.termsLabel, LegalLinks.termsOfUse)
            if !dynamicTypeSize.isAccessibilitySize {
                Text("·").foregroundColor(DS.Color.tertiaryText).accessibilityHidden(true)
            }
            link(LegalLinks.privacyLabel, LegalLinks.privacyPolicy)
        }
        .font(font)
    }

    private func link(_ label: String, _ url: URL) -> some View {
        Link(label, destination: url)
            .foregroundColor(DS.Color.accent)
            .accessibilityLabel(label)
            .accessibilityHint("Opens in Safari")
    }
}

#Preview {
    VStack(spacing: DS.Spacing.lg) {
        LegalLinksRow()
        LegalLinksRow(font: DS.Font.label, alignment: .leading)
    }
    .padding()
}
