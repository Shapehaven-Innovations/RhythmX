//  DesignSystem.swift

import SwiftUI

enum DS {

    // MARK: - Theme
    /// The selected moon theme. The id lives in `AppGroup.defaults` so the widgets follow it; a Plus theme
    /// is only drawn while Plus is active. In the app that means no grace (the app can always refresh the
    /// store); the widget extension keeps `Entitlement.plusGrace`, since it only has the cached expiry.
    enum Theme {
        static let storageKey = "themeID"
        static let washOpacity = 0.14

        static let plusGrace: TimeInterval =
            Bundle.main.bundleURL.pathExtension == "appex" ? Entitlement.plusGrace : 0

        static func resolve(defaults: UserDefaults = AppGroup.defaults, now: Date = Date(),
                            grace: TimeInterval = plusGrace) -> AppTheme {
            let id = defaults.string(forKey: storageKey) ?? AppTheme.defaultID
            let canUsePlus = Entitlement.load(from: defaults).isPlus(now: now, grace: grace)
            return AppTheme.effective(id: id, canUsePlus: canUsePlus)
        }

        static var current: AppTheme { resolve() }
    }

    // MARK: - Colors
    enum Color {
        static let phase1Default: SwiftUI.Color = makeAdaptive(
            light: (201, 124, 124), dark: (166,  96,  96)
        )
        static let phase2Default: SwiftUI.Color = makeAdaptive(
            light: (124, 166, 140), dark: ( 95, 138, 112)
        )
        static let phase3Default: SwiftUI.Color = makeAdaptive(
            light: (201, 168, 124), dark: (166, 136,  96)
        )
        static let phase4Default: SwiftUI.Color = makeAdaptive(
            light: (140, 124, 166), dark: (112,  95, 138)
        )

        static var phase1: SwiftUI.Color {
            guard let hex = AppGroup.defaults.string(forKey: "phaseColor1"),
                  let c = SwiftUI.Color(hex: hex) else { return phase1Default }
            return c
        }
        static var phase2: SwiftUI.Color {
            guard let hex = AppGroup.defaults.string(forKey: "phaseColor2"),
                  let c = SwiftUI.Color(hex: hex) else { return phase2Default }
            return c
        }
        static var phase3: SwiftUI.Color {
            guard let hex = AppGroup.defaults.string(forKey: "phaseColor3"),
                  let c = SwiftUI.Color(hex: hex) else { return phase3Default }
            return c
        }
        static var phase4: SwiftUI.Color {
            guard let hex = AppGroup.defaults.string(forKey: "phaseColor4"),
                  let c = SwiftUI.Color(hex: hex) else { return phase4Default }
            return c
        }

        // Theme palette (page, card, accent, moon, waves). Resolved on every read through `DS.Theme.current`,
        // so a view that redraws after the theme or the entitlement changes picks the new colours up.
        static var cardBackground: SwiftUI.Color { themed(\.card) }
        static var pageBackground: SwiftUI.Color { themed(\.page) }
        /// The tab bar: the card colour with about 7% accent in it.
        static var tabBar: SwiftUI.Color { themed(AppTheme.tabBar) }

        static var accent: SwiftUI.Color    { themed(\.accent) }
        static var onAccent: SwiftUI.Color  { themed(\.onAccent) }
        static var moon: SwiftUI.Color      { themed(\.moon) }
        static var waveBack: SwiftUI.Color  { themed(\.waveBack) }
        static var waveMid: SwiftUI.Color   { themed(\.waveMid) }
        static var waveFront: SwiftUI.Color { themed(\.waveFront) }
        /// Text and strokes drawn over the waves (`AppTheme.onWave`).
        static var onWave: SwiftUI.Color {
            let theme = DS.Theme.current
            return adaptive(light: AppTheme.onWave(theme, theme.light), dark: AppTheme.onWave(theme, theme.dark))
        }

        /// The theme's light accent and moon in both appearances: for the one card that is always drawn on a
        /// dark brand colour (Settings > Private by design), so it does not invert in dark mode.
        static var brand: SwiftUI.Color     { let p = DS.Theme.current.light; return adaptive(light: p.accent, dark: p.accent) }
        static var brandMoon: SwiftUI.Color { let p = DS.Theme.current.light; return adaptive(light: p.moon, dark: p.moon) }

        static let separator = SwiftUI.Color(UIColor.separator)

        /// Blush keeps the system label colours it always had; the other themes use their own ink and muted.
        static var primaryText: SwiftUI.Color {
            let theme = DS.Theme.current
            return theme == .blush ? SwiftUI.Color(UIColor.label) : adaptive(light: theme.light.ink, dark: theme.dark.ink)
        }
        static var secondaryText: SwiftUI.Color {
            let theme = DS.Theme.current
            return theme == .blush ? SwiftUI.Color(UIColor.secondaryLabel) : adaptive(light: theme.light.muted, dark: theme.dark.muted)
        }
        static var tertiaryText: SwiftUI.Color {
            let theme = DS.Theme.current
            return theme == .blush ? SwiftUI.Color(UIColor.tertiaryLabel)
                                   : adaptive(light: theme.light.muted, dark: theme.dark.muted).opacity(0.6)
        }

        private static func themed(_ key: KeyPath<Palette, RGB>) -> SwiftUI.Color {
            let theme = DS.Theme.current
            return adaptive(light: theme.light[keyPath: key], dark: theme.dark[keyPath: key])
        }

        private static func themed(_ derive: (Palette) -> RGB) -> SwiftUI.Color {
            let theme = DS.Theme.current
            return adaptive(light: derive(theme.light), dark: derive(theme.dark))
        }

        /// One colour for light and one for dark, as a dynamic colour. Also used by the theme picker swatches.
        static func adaptive(light: RGB, dark: RGB) -> SwiftUI.Color {
            makeAdaptive(light: (CGFloat(light.r), CGFloat(light.g), CGFloat(light.b)),
                         dark: (CGFloat(dark.r), CGFloat(dark.g), CGFloat(dark.b)))
        }

        static func solid(_ rgb: RGB) -> SwiftUI.Color {
            SwiftUI.Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
        }

        private static func makeAdaptive(
            light: (CGFloat, CGFloat, CGFloat),
            dark:  (CGFloat, CGFloat, CGFloat)
        ) -> SwiftUI.Color {
            let lightColor = UIColor(red: light.0 / 255, green: light.1 / 255, blue: light.2 / 255, alpha: 1)
            let darkColor  = UIColor(red: dark.0  / 255, green: dark.1  / 255, blue: dark.2  / 255, alpha: 1)
            let adaptive   = UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor }
            return SwiftUI.Color(adaptive)
        }
    }

    // MARK: - Typography
    enum Font {
        static let displayTitle  = SwiftUI.Font.largeTitle.bold()
        static let sectionHeader = SwiftUI.Font.headline.weight(.semibold)
        static let body          = SwiftUI.Font.body
        static let label         = SwiftUI.Font.subheadline
        static let caption       = SwiftUI.Font.footnote
        static let micro         = SwiftUI.Font.caption2
    }

    // MARK: - Spacing (4pt grid)
    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius
    enum Radius {
        static let card:   CGFloat = 16
        static let chip:   CGFloat = 8
        static let button: CGFloat = 12
    }
}

// MARK: - Page background with the theme's top wash

/// The page colour with a soft wash of the accent behind the status bar and the large title.
struct ThemedPageBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            DS.Color.pageBackground
            LinearGradient(colors: [DS.Color.accent.opacity(DS.Theme.washOpacity), DS.Color.accent.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 240)
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// `.themedPage()` plus the theme's top wash.
    func themedPage() -> some View {
        background(ThemedPageBackground().ignoresSafeArea())
    }
}

// MARK: - Event.EventType helpers
extension Event.EventType {
    var phaseNumber: Int {
        switch self {
        case .menstrual:  return 1
        case .follicular: return 2
        case .ovulation:  return 3
        case .luteal:     return 4
        }
    }

    var defaultPhaseColor: Color {
        switch self {
        case .menstrual:  return DS.Color.phase1Default
        case .follicular: return DS.Color.phase2Default
        case .ovulation:  return DS.Color.phase3Default
        case .luteal:     return DS.Color.phase4Default
        }
    }

    var phaseColor: Color {
        switch self {
        case .menstrual:  return DS.Color.phase1
        case .follicular: return DS.Color.phase2
        case .ovulation:  return DS.Color.phase3
        case .luteal:     return DS.Color.phase4
        }
    }

    var displayName: String {
        rawValue.capitalized + " Phase"
    }
}
