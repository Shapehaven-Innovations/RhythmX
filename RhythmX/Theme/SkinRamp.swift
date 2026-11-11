//  SkinRamp.swift
//
//  The five-step severity ramp for skin cells. The card colour is mixed toward the theme accent, or toward ink
//  when the accent's hue sits within `hueGuardDegrees` of any fixed phase colour. Each step's text is ink or card,
//  whichever contrasts more; a step that falls short of 4.5:1 is moved toward the card in small nudges.
//  Phase colours are never a fill here.

import SwiftUI

struct SkinRamp: Equatable {
    static let steps: [Double] = [0.10, 0.28, 0.48, 0.72, 1.00]
    static let hueGuardDegrees = 30.0
    static let minimumTextContrast = 4.5
    static let nudge = 0.02

    /// Fill colours for buckets 1...5.
    let fills: [RGB]
    /// Text colour per bucket 1...5.
    let text: [RGB]
    /// Bucket 0 fill.
    let empty: RGB
    /// Bucket 0 text.
    let emptyText: RGB
    let usesNeutralTarget: Bool
    /// The mix amount actually used per step after nudging.
    let resolvedSteps: [Double]

    private static let phases: [Event.EventType] = [.menstrual, .follicular, .ovulation, .luteal]

    static func make(theme: AppTheme, isDark: Bool) -> SkinRamp {
        let p = isDark ? theme.dark : theme.light
        let neutral = phases.contains { hueDistance(p.accent, AuraPalette.phaseRGB($0, isDark: isDark)) < hueGuardDegrees }
        let target = neutral ? p.ink : p.accent

        func textFor(_ fill: RGB) -> RGB { contrast(fill, p.ink) >= contrast(fill, p.card) ? p.ink : p.card }

        var fills: [RGB] = [], text: [RGB] = [], used: [Double] = []
        for (i, step) in steps.enumerated() {
            let floor = i == 0 ? nudge : (used[i - 1] + nudge)
            var t = step
            var fill = RGB.mix(p.card, target, t)
            var ink = textFor(fill)
            while contrast(fill, ink) < minimumTextContrast {
                let next = ((t - nudge) * 100).rounded() / 100
                guard next >= floor - 1e-9 else { break }
                t = next
                fill = RGB.mix(p.card, target, t)
                ink = textFor(fill)
            }
            fills.append(fill); text.append(ink); used.append(t)
        }
        return SkinRamp(fills: fills, text: text, empty: RGB.mix(p.card, p.ink, 0.06), emptyText: p.muted,
                        usesNeutralTarget: neutral, resolvedSteps: used)
    }

    /// nil or 0 -> 0 (empty); 1...10 -> 1; 11...20 -> 2; 21...35 -> 3; 36...50 -> 4; over 50 -> 5.
    static func bucket(percent: Int?) -> Int {
        guard let percent, percent > 0 else { return 0 }
        switch percent {
        case ...10: return 1
        case ...20: return 2
        case ...35: return 3
        case ...50: return 4
        default:    return 5
        }
    }

    func fill(percent: Int?) -> RGB {
        let b = Self.bucket(percent: percent)
        return b == 0 ? empty : fills[b - 1]
    }

    func textColour(percent: Int?) -> RGB {
        let b = Self.bucket(percent: percent)
        return b == 0 ? emptyText : text[b - 1]
    }

    // MARK: Colour maths

    /// HSV hue in degrees, 0..<360; 0 for a grey.
    static func hueDegrees(_ c: RGB) -> Double {
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let maxV = max(r, g, b), minV = min(r, g, b), d = maxV - minV
        guard d > 0 else { return 0 }
        var h: Double
        if maxV == r { h = (g - b) / d }
        else if maxV == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h *= 60
        if h < 0 { h += 360 }
        return h >= 360 ? h - 360 : h
    }

    /// The shorter way round the hue circle, 0...180.
    static func hueDistance(_ a: RGB, _ b: RGB) -> Double {
        let d = abs(hueDegrees(a) - hueDegrees(b))
        return min(d, 360 - d)
    }

    /// WCAG 2.x relative luminance.
    static func luminance(_ c: RGB) -> Double {
        func channel(_ v: Int) -> Double {
            let s = Double(v) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    /// WCAG 2.x contrast ratio, 1...21.
    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    // MARK: SwiftUI

    /// Ramps for the current theme in both appearances, resolved on read like `DS.Color`.
    static var current: (light: SkinRamp, dark: SkinRamp) {
        let theme = DS.Theme.current
        return (make(theme: theme, isDark: false), make(theme: theme, isDark: true))
    }

    static func colour(_ keyPath: KeyPath<SkinRamp, RGB>) -> Color {
        let ramps = current
        return DS.Color.adaptive(light: ramps.light[keyPath: keyPath], dark: ramps.dark[keyPath: keyPath])
    }

    /// The figure behind the regions: ink mixed 10% into the card, so it reads on the card and on the page.
    static var silhouetteColour: Color { mapTint(0.10) }
    /// The same figure when it sits on the page (the pick map), where a card-based tint would vanish.
    static var pageSilhouetteColour: Color { mapTint(0.14, onPage: true) }
    /// A region with nothing logged: the same tint as the figure; the gaps between zones and the outline keep the shapes apart.
    static var regionColour: Color { mapTint(0.10) }

    private static func mapTint(_ amount: Double, onPage: Bool = false) -> Color {
        let theme = DS.Theme.current
        let light = onPage ? theme.light.page : theme.light.card
        let dark = onPage ? theme.dark.page : theme.dark.card
        return DS.Color.adaptive(light: RGB.mix(light, theme.light.ink, amount),
                                 dark: RGB.mix(dark, theme.dark.ink, amount))
    }

    static func fillColour(percent: Int?) -> Color {
        let ramps = current
        return DS.Color.adaptive(light: ramps.light.fill(percent: percent), dark: ramps.dark.fill(percent: percent))
    }

    static func textColor(percent: Int?) -> Color {
        let ramps = current
        return DS.Color.adaptive(light: ramps.light.textColour(percent: percent), dark: ramps.dark.textColour(percent: percent))
    }
}
