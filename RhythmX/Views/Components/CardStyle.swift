//  CardStyle.swift

import SwiftUI

/// The card every screen uses: the theme's card colour with a little depth over the living background,
/// a hairline highlight along the top edge and a soft shadow tinted with the theme (black at night).
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardSurface(cornerRadius: DS.Radius.card))
    }
}

/// The card surface on its own, for tiles and other shapes that set their own padding and size.
struct CardSurface: View {
    var cornerRadius: CGFloat = DS.Radius.card
    var fill: Color = DS.Color.cardBackground

    /// White hairline: strong on light cards, a faint glint on dark ones.
    static let highlight = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 1, alpha: 0.75) })

    /// Light: a plum-tinted shadow (the design's 60, 20, 50 at 10%), dark: black at 35%.
    static let shadow = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0, alpha: 0.35) : UIColor(red: 60 / 255, green: 20 / 255, blue: 50 / 255, alpha: 0.12) })

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(fill)
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [Self.highlight, Self.highlight.opacity(0)],
                                                  startPoint: .top, endPoint: .center), lineWidth: 1)
            )
            .shadow(color: Self.shadow, radius: 14, x: 0, y: 8)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
