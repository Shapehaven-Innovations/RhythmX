//  AppTheme.swift
//
//  The moon themes. Pure values, compiled into the app and the widget extension; `DS.Color` resolves
//  through the selected theme. Phase colours are not part of a theme: a phase keeps the same colour
//  everywhere so that colour always encodes the same data.

import Foundation

struct RGB: Equatable {
    let r: Int
    let g: Int
    let b: Int

    /// `a` moved `t` of the way toward `b` (0 is `a`, 1 is `b`), rounded per channel.
    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        func channel(_ x: Int, _ y: Int) -> Int { Int((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
        return RGB(r: channel(a.r, b.r), g: channel(a.g, b.g), b: channel(a.b, b.b))
    }
}

struct Palette: Equatable {
    let page: RGB
    let card: RGB
    let ink: RGB
    let muted: RGB
    let accent: RGB
    let onAccent: RGB
    let moon: RGB
    let waveBack: RGB
    let waveMid: RGB
    let waveFront: RGB

    /// A palette whose three wave colours are the accent mixed toward the moon colour in three steps.
    static func derivingWaves(page: RGB, card: RGB, ink: RGB, muted: RGB, accent: RGB, onAccent: RGB, moon: RGB) -> Palette {
        let steps = AppTheme.waveSteps
        return Palette(page: page, card: card, ink: ink, muted: muted, accent: accent, onAccent: onAccent, moon: moon,
                       waveBack: RGB.mix(accent, moon, steps.back),
                       waveMid: RGB.mix(accent, moon, steps.mid),
                       waveFront: RGB.mix(accent, moon, steps.front))
    }
}

struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let isPlus: Bool
    let light: Palette
    let dark: Palette

    static let defaultID = "blush"

    /// How far from the accent toward the moon colour each wave layer sits (back is the lightest, drawn first).
    static let waveSteps = (back: 0.65, mid: 0.40, front: 0.15)

    /// The tab bar is the card colour with a little accent in it.
    static func tabBar(_ p: Palette) -> RGB { RGB.mix(p.card, p.accent, 0.07) }

    /// Text drawn over the waves. Blush keeps white over its plum waves in both appearances. A Plus theme's
    /// waves are derived from its accent, so it uses `onAccent`: white on the dark light-mode accents and dark
    /// on the light dark-mode accents, where white would not read.
    static func onWave(_ theme: AppTheme, _ palette: Palette) -> RGB {
        theme == .blush ? RGB(r: 255, g: 255, b: 255) : palette.onAccent
    }

    // MARK: Catalogue

    /// Blush is the app's original palette and does not change. Its ink and muted values are the system label
    /// colours (`DS.Color` keeps using `UIColor.label` and `UIColor.secondaryLabel` for Blush).
    static let blush = AppTheme(
        id: "blush", name: "Blush", isPlus: false,
        light: Palette(page: RGB(r: 251, g: 241, b: 243), card: RGB(r: 255, g: 255, b: 255),
                       ink: RGB(r: 0, g: 0, b: 0), muted: RGB(r: 60, g: 60, b: 67),
                       accent: RGB(r: 94, g: 38, b: 79), onAccent: RGB(r: 255, g: 255, b: 255),
                       moon: RGB(r: 240, g: 179, b: 196),
                       waveBack: RGB(r: 196, g: 130, b: 170), waveMid: RGB(r: 176, g: 104, b: 154), waveFront: RGB(r: 139, g: 63, b: 107)),
        dark: Palette(page: RGB(r: 27, g: 15, b: 30), card: RGB(r: 43, g: 24, b: 48),
                      ink: RGB(r: 255, g: 255, b: 255), muted: RGB(r: 235, g: 235, b: 245),
                      accent: RGB(r: 232, g: 165, b: 184), onAccent: RGB(r: 27, g: 15, b: 30),
                      moon: RGB(r: 244, g: 228, b: 236),
                      waveBack: RGB(r: 196, g: 138, b: 168), waveMid: RGB(r: 154, g: 92, b: 134), waveFront: RGB(r: 58, g: 27, b: 58))
    )

    /// Indigo on a cool blue page.
    static let blueMoon = AppTheme(
        id: "blueMoon", name: "Blue Moon", isPlus: true,
        light: .derivingWaves(page: RGB(r: 0xDC, g: 0xE5, b: 0xF7), card: RGB(r: 0xF4, g: 0xF7, b: 0xFD),
                              ink: RGB(r: 0x13, g: 0x1B, b: 0x3D), muted: RGB(r: 0x4A, g: 0x55, b: 0x80),
                              accent: RGB(r: 0x2A, g: 0x3C, b: 0x8F), onAccent: RGB(r: 0xFF, g: 0xFF, b: 0xFF),
                              moon: RGB(r: 0x8F, g: 0xA6, b: 0xE8)),
        dark: .derivingWaves(page: RGB(r: 0x0A, g: 0x10, b: 0x30), card: RGB(r: 0x15, g: 0x1D, b: 0x4A),
                             ink: RGB(r: 0xE8, g: 0xED, b: 0xFF), muted: RGB(r: 0xA3, g: 0xB0, b: 0xDD),
                             accent: RGB(r: 0x9F, g: 0xB4, b: 0xFF), onAccent: RGB(r: 0x0A, g: 0x10, b: 0x30),
                             moon: RGB(r: 0xC7, g: 0xD3, b: 0xFF))
    )

    /// Amber on a warm wheat page.
    static let harvestMoon = AppTheme(
        id: "harvestMoon", name: "Harvest Moon", isPlus: true,
        light: .derivingWaves(page: RGB(r: 0xF6, g: 0xDD, b: 0xB4), card: RGB(r: 0xFF, g: 0xF6, b: 0xE6),
                              ink: RGB(r: 0x2B, g: 0x17, b: 0x06), muted: RGB(r: 0x6B, g: 0x4F, b: 0x34),
                              accent: RGB(r: 0x7A, g: 0x3E, b: 0x0A), onAccent: RGB(r: 0xFF, g: 0xFF, b: 0xFF),
                              moon: RGB(r: 0xE8, g: 0xA2, b: 0x3A)),
        dark: .derivingWaves(page: RGB(r: 0x2A, g: 0x1A, b: 0x08), card: RGB(r: 0x3D, g: 0x27, b: 0x11),
                             ink: RGB(r: 0xFB, g: 0xEF, b: 0xD9), muted: RGB(r: 0xD2, g: 0xB7, b: 0x8E),
                             accent: RGB(r: 0xFF, g: 0xB8, b: 0x4D), onAccent: RGB(r: 0x2A, g: 0x1A, b: 0x08),
                             moon: RGB(r: 0xFF, g: 0xD2, b: 0x8A))
    )

    /// Graphite with a copper accent; the boldest, most data-forward.
    static let eclipse = AppTheme(
        id: "eclipse", name: "Eclipse", isPlus: true,
        light: .derivingWaves(page: RGB(r: 0xE3, g: 0xE4, b: 0xE9), card: RGB(r: 0xF7, g: 0xF7, b: 0xF9),
                              ink: RGB(r: 0x14, g: 0x16, b: 0x1C), muted: RGB(r: 0x55, g: 0x59, b: 0x66),
                              accent: RGB(r: 0xA9, g: 0x46, b: 0x1A), onAccent: RGB(r: 0xFF, g: 0xFF, b: 0xFF),
                              moon: RGB(r: 0xAE, g: 0xB3, b: 0xC2)),
        dark: .derivingWaves(page: RGB(r: 0x0C, g: 0x0D, b: 0x10), card: RGB(r: 0x1B, g: 0x1D, b: 0x23),
                             ink: RGB(r: 0xEE, g: 0xEF, b: 0xF3), muted: RGB(r: 0xA0, g: 0xA4, b: 0xB2),
                             accent: RGB(r: 0xF0, g: 0xA3, b: 0x6B), onAccent: RGB(r: 0x0C, g: 0x0D, b: 0x10),
                             moon: RGB(r: 0xD5, g: 0xD8, b: 0xE0))
    )

    static let all: [AppTheme] = [blush, blueMoon, harvestMoon, eclipse]

    static func named(_ id: String) -> AppTheme? { all.first { $0.id == id } }

    /// The theme to draw for a stored id. A Plus theme without Plus (and an unknown id) shows as Blush; the
    /// stored id is not changed, so the theme comes back on its own when Plus is active again.
    static func effective(id: String, canUsePlus: Bool) -> AppTheme {
        guard let theme = named(id) else { return blush }
        return theme.isPlus && !canUsePlus ? blush : theme
    }
}
