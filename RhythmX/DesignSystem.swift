//  DesignSystem.swift

import SwiftUI

enum DS {

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
            guard let hex = UserDefaults.standard.string(forKey: "phaseColor1"),
                  let c = SwiftUI.Color(hex: hex) else { return phase1Default }
            return c
        }
        static var phase2: SwiftUI.Color {
            guard let hex = UserDefaults.standard.string(forKey: "phaseColor2"),
                  let c = SwiftUI.Color(hex: hex) else { return phase2Default }
            return c
        }
        static var phase3: SwiftUI.Color {
            guard let hex = UserDefaults.standard.string(forKey: "phaseColor3"),
                  let c = SwiftUI.Color(hex: hex) else { return phase3Default }
            return c
        }
        static var phase4: SwiftUI.Color {
            guard let hex = UserDefaults.standard.string(forKey: "phaseColor4"),
                  let c = SwiftUI.Color(hex: hex) else { return phase4Default }
            return c
        }

        static let cardBackground = makeAdaptive(light: (255, 255, 255), dark: (43, 24, 48))
        static let pageBackground = makeAdaptive(light: (251, 241, 243), dark: (27, 15, 30))

        // Brand palette (moon and ocean)
        static let accent    = makeAdaptive(light: (94, 38, 79),    dark: (232, 165, 184))
        static let onAccent  = makeAdaptive(light: (255, 255, 255), dark: (27, 15, 30))
        static let moon      = makeAdaptive(light: (240, 179, 196), dark: (244, 228, 236))
        static let waveBack  = makeAdaptive(light: (196, 130, 170), dark: (196, 138, 168))
        static let waveMid   = makeAdaptive(light: (176, 104, 154), dark: (154, 92, 134))
        static let waveFront = makeAdaptive(light: (139, 63, 107),  dark: (58, 27, 58))

        static let separator       = SwiftUI.Color(UIColor.separator)
        static let primaryText     = SwiftUI.Color(UIColor.label)
        static let secondaryText   = SwiftUI.Color(UIColor.secondaryLabel)
        static let tertiaryText    = SwiftUI.Color(UIColor.tertiaryLabel)

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
