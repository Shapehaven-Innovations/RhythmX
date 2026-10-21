//  AuraPalette.swift
//
//  The colours of the living page background (Phase Aura): a soft 3 x 3 mesh of the current phase colour,
//  the theme accent and the moon over the page colour, warmer toward evening. Pure values so the contrast
//  rules (text on the aura, the moon disc against the page) are unit tested for every theme, appearance
//  and phase. Every mesh colour is already blended onto the page, so it is opaque and testable as drawn.

import Foundation

struct AuraPalette: Equatable {
    /// How many stars a page shows and how bright they are.
    struct Stars: Equatable {
        /// Small moon-coloured dots.
        let count: Int
        /// Extra white stars (Eclipse at night).
        let brightCount: Int
        /// Four-point glints.
        let glints: Int
        /// Opacity of the whole field.
        let opacity: Double

        static let none = Stars(count: 0, brightCount: 0, glints: 0, opacity: 0)
        var isVisible: Bool { opacity > 0 && count + brightCount + glints > 0 }
    }

    enum TimeOfDay: Equatable {
        case morning, afternoon, evening, night

        init(hour: Int) {
            switch hour {
            case 5..<12:  self = .morning
            case 12..<17: self = .afternoon
            case 17..<22: self = .evening
            default:      self = .night
            }
        }
    }

    /// The page colour under everything.
    let page: RGB
    /// Nine colours, row by row from the top left (a `MeshGradient` of width and height 3).
    let mesh: [RGB]
    /// The moon disc's edge (and the moon glyph colour): at least 3:1 against the page in every theme.
    let disc: RGB
    /// The disc's lit highlight (moon light over the card colour).
    let discLight: RGB
    /// The disc body colour (the card colour).
    let discBody: RGB
    /// Glow around the disc: the phase colour.
    let glow: RGB
    /// Low wave layers drawn at the bottom in dark appearance (back to front).
    let waves: [RGB]
    let stars: Stars
    let isDark: Bool

    // MARK: - Making

    static func make(phase: Event.EventType?, theme: AppTheme, isDark: Bool, hour: Int) -> AuraPalette {
        let p = isDark ? theme.dark : theme.light
        let time = TimeOfDay(hour: hour)
        // On light pages the tints are lifted toward white so they glow without darkening the page under text.
        let white = RGB(r: 255, g: 255, b: 255)
        func tint(_ c: RGB, _ lift: Double) -> RGB { isDark ? c : RGB.mix(c, white, lift) }
        // Without a phase (Menopause, or no cycle yet) the theme accent leads, softened toward the page.
        let rawPhase = phase.map { phaseRGB($0, isDark: isDark) } ?? RGB.mix(p.accent, isDark ? p.page : p.moon, 0.45)
        let phaseColor = tint(rawPhase, 0.50)
        let warm = tint(phaseRGB(.ovulation, isDark: isDark), 0.25)
        let accent = tint(p.accent, 0.45)

        // Blend strengths, tuned so ink and muted text keep 4.5:1 on every mesh colour (AuraPalette tests).
        let a: (phaseTop: Double, accent: Double, moonSide: Double, phaseLow: Double, centre: Double, horizon: Double) =
            isDark ? (0.32, 0.18, 0.16, 0.18, 0.05, 0.20) : (0.40, 0.30, 0.36, 0.30, 0.12, 0.34)

        func over(_ c: RGB, _ t: Double) -> RGB { RGB.mix(p.page, c, t) }

        // Morning lifts a warm light in at the top; evening is the afternoon light turned warmer (red up, blue
        // down) with a golden horizon; night is moonlight only.
        let topCentre: RGB
        let horizon: RGB
        let lowRight: RGB
        switch time {
        case .morning:
            topCentre = over(warm, isDark ? 0.24 : 0.30)
            horizon = over(p.moon, a.horizon * 0.8)
            lowRight = over(p.moon, 0.10)
        case .afternoon, .evening:
            topCentre = over(RGB.mix(phaseColor, accent, 0.5), a.accent * 0.8)
            horizon = over(time == .evening ? RGB.mix(p.moon, warm, 0.6) : p.moon, a.horizon)
            lowRight = over(p.moon, 0.12)
        case .night:
            topCentre = over(RGB.mix(phaseColor, accent, 0.5), a.accent)
            horizon = over(p.moon, a.horizon * 0.9)
            lowRight = over(p.moon, 0.08)
        }

        var mesh = [
            over(phaseColor, a.phaseTop), topCentre, over(accent, a.accent),
            over(phaseColor, a.phaseLow * 0.6), over(p.moon, a.centre), over(p.moon, a.moonSide),
            over(phaseColor, a.phaseLow), horizon, lowRight,
        ]
        if time == .evening { mesh = mesh.map { warmed($0, by: isDark ? 6 : 8) } }

        let waves: [RGB]
        if theme == .blush {
            waves = [theme.light.waveBack, theme.light.waveMid, theme.light.waveFront]
        } else {
            let black = RGB(r: 0, g: 0, b: 0)
            waves = [p.accent, RGB.mix(p.accent, black, 0.28), RGB.mix(p.accent, black, 0.52)]
        }

        return AuraPalette(page: p.page, mesh: mesh, disc: discRGB(theme: theme, isDark: isDark),
                           discLight: RGB.mix(p.card, p.moon, isDark ? 0.40 : 0.46), discBody: p.card,
                           glow: rawPhase, waves: waves, stars: stars(theme: theme, isDark: isDark),
                           isDark: isDark)
    }

    /// `c` with red raised and blue lowered by `k` (clamped): the same light, a little warmer.
    static func warmed(_ c: RGB, by k: Int) -> RGB {
        RGB(r: min(255, c.r + k), g: c.g, b: max(0, c.b - k))
    }

    /// The four fixed phase colours (`DS.Color.phase1Default`...), light and dark.
    static func phaseRGB(_ phase: Event.EventType, isDark: Bool) -> RGB {
        switch (phase, isDark) {
        case (.menstrual, false):  return RGB(r: 201, g: 124, b: 124)
        case (.menstrual, true):   return RGB(r: 166, g: 96, b: 96)
        case (.follicular, false): return RGB(r: 124, g: 166, b: 140)
        case (.follicular, true):  return RGB(r: 95, g: 138, b: 112)
        case (.ovulation, false):  return RGB(r: 201, g: 168, b: 124)
        case (.ovulation, true):   return RGB(r: 166, g: 136, b: 96)
        case (.luteal, false):     return RGB(r: 140, g: 124, b: 166)
        case (.luteal, true):      return RGB(r: 112, g: 95, b: 138)
        }
    }

    /// The moon disc edge. Dark pages use the theme's moon colour; light pages a deeper moon tone that keeps
    /// 3:1 against the light page (the design's `--disc`).
    static func discRGB(theme: AppTheme, isDark: Bool) -> RGB {
        if isDark { return theme.dark.moon }
        switch theme.id {
        case AppTheme.blueMoon.id:    return RGB(r: 0x5E, g: 0x73, b: 0xBC)
        case AppTheme.harvestMoon.id: return RGB(r: 0x9A, g: 0x5F, b: 0x18)
        case AppTheme.eclipse.id:     return RGB(r: 0x6F, g: 0x73, b: 0x7F)
        default:                      return RGB(r: 0xA8, g: 0x6C, b: 0x87)
        }
    }

    /// No stars on light pages; a subtle field in dark themes; a dense, bright sky in Eclipse at night.
    static func stars(theme: AppTheme, isDark: Bool) -> Stars {
        guard isDark else { return .none }
        if theme == .eclipse { return Stars(count: 46, brightCount: 70, glints: 5, opacity: 1.0) }
        return Stars(count: 40, brightCount: 0, glints: 3, opacity: 0.55)
    }

    /// Mean of (red minus blue) over the mesh: higher is warmer. Used by tests and to tune the evening glow.
    var warmth: Double {
        Double(mesh.reduce(0) { $0 + ($1.r - $1.b) }) / Double(max(mesh.count, 1))
    }
}

// MARK: - Star positions

/// One star in unit coordinates (0...1 across and down the page).
struct AuraStar: Equatable {
    let x: Double
    let y: Double
    let radius: Double
    let opacity: Double
    /// Twinkles when motion is allowed.
    let twinkles: Bool
    let kind: Kind

    enum Kind: Equatable { case dot, bright, glint }
}

enum AuraStarField {
    /// A deterministic field: the same seed and counts always give the same stars, so the sky never jumps
    /// between redraws or launches. Park and Miller's minimal standard generator, as in the design files.
    static func stars(seed: Int, stars: AuraPalette.Stars) -> [AuraStar] {
        var state = max(seed, 1) % 2_147_483_647
        func next() -> Double {
            state = (state &* 16_807) % 2_147_483_647
            return Double(state) / 2_147_483_647
        }
        var result: [AuraStar] = []
        for i in 0..<stars.count {
            let x = next(), y = next(), r = next() * 1.0 + 0.35, o = 0.3 + next() * 0.5
            result.append(AuraStar(x: x, y: y, radius: r, opacity: o, twinkles: i % 3 == 0, kind: .dot))
        }
        for i in 0..<stars.brightCount {
            let x = next(), y = next(), r = next() * 1.4 + 0.3, o = 0.35 + next() * 0.55
            result.append(AuraStar(x: x, y: y, radius: r, opacity: o, twinkles: i % 4 == 0, kind: .bright))
        }
        for _ in 0..<stars.glints {
            let x = next(), y = next() * 0.7, s = 3 + next() * 3
            result.append(AuraStar(x: x, y: y, radius: s, opacity: 0.85, twinkles: true, kind: .glint))
        }
        return result
    }
}
