//  PhaseAuraBackground.swift
//
//  The living page background (Phase Aura): a soft mesh of the current phase colour, the theme accent and the
//  moon (`AuraPalette`), a quiet starfield on dark pages (densest in Eclipse), low waves at night, and on Today
//  a slow drift with the occasional shooting star. Every page gets it through `.themedPage()`.
//
//  Cost: one MeshGradient and one Canvas. Pages are still by default (no timeline ticks at all); Today asks
//  for motion, which runs at 15 frames a second at most and stops for Reduce Motion and Low Power Mode. The
//  layers are an Equatable view, so a state change elsewhere on the page does not rebuild them.

import SwiftUI
import Combine

extension EnvironmentValues {
    /// The current cycle phase the aura is tinted with; nil (Menopause, or no cycle yet) uses the accent.
    @Entry var auraPhase: Event.EventType? = nil
    /// True while continuous motion may run (`AmbientMotionScope`): the page is on screen, the app is active,
    /// and neither Reduce Motion nor Low Power Mode is on. Still by default.
    @Entry var ambientMotion: Bool = false
}

// MARK: - Ambient motion

/// The one rule and clock for continuous motion on Today (the aura drift, the breathing moon, the floating
/// tiles): at most 15 frames a second, and none at all with Reduce Motion, in Low Power Mode, while the app is
/// not active or while Today is not on screen.
enum AmbientMotion {
    static let framesPerSecond = 15
    static var minimumInterval: Double { 1.0 / Double(framesPerSecond) }

    static func isOn(reduceMotion: Bool, lowPower: Bool, active: Bool, visible: Bool) -> Bool {
        !reduceMotion && !lowPower && active && visible
    }

    /// The moon's breath, 0 (rest) to 1 (full), on a 6.4 second cycle. 0 without a clock.
    static func breath(at t: Double?) -> Double {
        guard let t else { return 0 }
        return (1 - cos(t / 6.4 * 2 * .pi)) / 2
    }

    /// A tile's float, from 2 pt down to 3 pt up, each tile on its own slow period. 0 without a clock.
    static func floatOffset(index: Int, at t: Double?) -> Double {
        guard let t else { return 0 }
        let period = 2 * (2.6 + Double(index % 3) * 0.5)
        let wave = (1 - cos(t / period * 2 * .pi + Double(index))) / 2   // 0 to 1
        return 2 - 5 * wave
    }
}

/// Sets `\.ambientMotion` for a page: on only while it is on screen, the app is active, and neither Reduce
/// Motion nor Low Power Mode is on.
struct AmbientMotionScope: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .environment(\.ambientMotion, AmbientMotion.isOn(reduceMotion: reduceMotion, lowPower: lowPower,
                                                             active: scenePhase == .active, visible: visible))
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: RunLoop.main)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}

extension View {
    func ambientMotionScope() -> some View { modifier(AmbientMotionScope()) }
}

struct PhaseAuraBackground: View {
    /// Slow drift and twinkling. Only Today asks for it.
    var animated: Bool = false
    /// A rare shooting star on dark pages (Today only).
    var shootingStars: Bool = false

    @Environment(\.auraPhase) private var phase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ambientMotion) private var ambientMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    static let starSeed = 5

    var body: some View {
        let palette = AuraPalette.make(phase: phase, theme: DS.Theme.current, isDark: colorScheme == .dark,
                                       hour: Calendar.current.component(.hour, from: Date()))
        // `ambientMotion` also stops it while Today is off screen or the app is not active.
        let moving = animated && ambientMotion && !reduceMotion && !lowPower
        AuraLayers(palette: palette,
                   stars: AuraStarField.stars(seed: Self.starSeed, stars: palette.stars),
                   moving: moving,
                   shooting: moving && shootingStars && palette.isDark)
            .equatable()
            .accessibilityHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: RunLoop.main)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}

/// The drawn layers. Equatable on its inputs so it only redraws when the palette or motion changes.
private struct AuraLayers: View, Equatable {
    let palette: AuraPalette
    let stars: [AuraStar]
    let moving: Bool
    let shooting: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: AmbientMotion.minimumInterval, paused: !moving)) { timeline in
            let t = moving ? timeline.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                MeshGradient(width: 3, height: 3, points: Self.points(t), colors: palette.mesh.map(DS.Color.solid),
                             smoothsColors: true)
                if palette.isDark {
                    NightWaves(colors: palette.waves)
                }
                if palette.stars.isVisible {
                    AuraStarCanvas(stars: stars, moon: DS.Color.solid(palette.disc), opacity: palette.stars.opacity,
                                   time: moving ? t : nil, shooting: shooting)
                }
            }
        }
    }

    /// The 3 x 3 mesh points. The centre and edge midpoints drift a few percent, each on its own slow period,
    /// so the light breathes without ever repeating visibly. t = 0 is the still layout.
    static func points(_ t: Double) -> [SIMD2<Float>] {
        func f(_ v: Double) -> Float { Float(v) }
        let still = t == 0
        let cx = 0.52 + (still ? 0 : 0.06 * sin(t / 7))
        let cy = 0.46 + (still ? 0 : 0.05 * cos(t / 9))
        return [
            [0, 0], [f(0.5 + (still ? 0 : 0.08 * sin(t / 11))), 0], [1, 0],
            [0, f(0.42 + (still ? 0 : 0.06 * sin(t / 8)))], [f(cx), f(cy)], [1, f(0.55 + (still ? 0 : 0.06 * cos(t / 10)))],
            [0, 1], [f(0.5 + (still ? 0 : 0.08 * cos(t / 12))), 1], [1, 1],
        ]
    }
}

/// Three low, faint waves at the bottom of dark pages (the app's waves, seen at night).
private struct NightWaves: View {
    let colors: [RGB]
    private static let opacities = [0.12, 0.16, 0.24]

    var body: some View {
        GeometryReader { geo in
            let h = min(240, geo.size.height * 0.3)
            ZStack(alignment: .bottom) {
                ForEach(0..<3, id: \.self) { i in
                    WaveShape(amplitude: 8, wavelength: max(geo.size.width / 2, 120), phase: CGFloat(i) * 1.1)
                        .fill(DS.Color.solid(colors[min(i, colors.count - 1)]).opacity(Self.opacities[i]))
                        .frame(height: h * (1 - CGFloat(i) * 0.22))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// The starfield, drawn in one Canvas pass. `time` nil draws it still (no twinkle).
struct AuraStarCanvas: View {
    let stars: [AuraStar]
    let moon: Color
    let opacity: Double
    let time: Double?
    var shooting: Bool = false

    /// One shooting star every `shootingPeriod` seconds, crossing in `shootingDuration`.
    static let shootingPeriod = 23.0
    static let shootingDuration = 1.1

    var body: some View {
        Canvas { context, size in
            for (i, star) in stars.enumerated() {
                var alpha = star.opacity * opacity
                if let time, star.twinkles {
                    alpha *= 0.55 + 0.45 * sin(time * 1.4 + Double(i) * 0.9)
                }
                let x = star.x * size.width, y = star.y * size.height
                switch star.kind {
                case .dot:
                    let r = star.radius
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(moon.opacity(alpha)))
                case .bright:
                    let r = star.radius
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(.white.opacity(alpha)))
                case .glint:
                    context.fill(Self.glint(x: x, y: y, size: star.radius), with: .color(.white.opacity(alpha)))
                }
            }
            if shooting, let time {
                let phase = time.truncatingRemainder(dividingBy: Self.shootingPeriod)
                if phase < Self.shootingDuration {
                    let p = phase / Self.shootingDuration
                    let start = CGPoint(x: size.width * 0.86, y: size.height * 0.10)
                    let travel = CGVector(dx: -size.width * 0.45, dy: size.width * 0.26)
                    let head = CGPoint(x: start.x + travel.dx * p, y: start.y + travel.dy * p)
                    let tail = CGPoint(x: head.x - travel.dx * 0.28, y: head.y - travel.dy * 0.28)
                    var path = Path()
                    path.move(to: tail)
                    path.addLine(to: head)
                    let fade = sin(p * .pi)
                    context.stroke(path, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.9 * fade)]),
                                                               startPoint: tail, endPoint: head),
                                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// A four-point glint centred on (x, y).
    static func glint(x: Double, y: Double, size s: Double) -> Path {
        var p = Path()
        let k = s * 0.12
        p.move(to: CGPoint(x: x, y: y - s))
        p.addCurve(to: CGPoint(x: x + s, y: y), control1: CGPoint(x: x + k, y: y - k), control2: CGPoint(x: x + k, y: y - k))
        p.addCurve(to: CGPoint(x: x, y: y + s), control1: CGPoint(x: x + k, y: y + k), control2: CGPoint(x: x + k, y: y + k))
        p.addCurve(to: CGPoint(x: x - s, y: y), control1: CGPoint(x: x - k, y: y + k), control2: CGPoint(x: x - k, y: y + k))
        p.addCurve(to: CGPoint(x: x, y: y - s), control1: CGPoint(x: x - k, y: y - k), control2: CGPoint(x: x - k, y: y - k))
        p.closeSubpath()
        return p
    }
}

// MARK: - Page background

/// The page background every screen uses: the Phase Aura, still unless asked otherwise.
struct ThemedPageBackground: View {
    var animated: Bool = false
    var shootingStars: Bool = false

    var body: some View {
        PhaseAuraBackground(animated: animated, shootingStars: shootingStars)
    }
}

extension View {
    /// The living page background behind this view (still by default; Today passes `animated: true`).
    func themedPage(animated: Bool = false, shootingStars: Bool = false) -> some View {
        background(ThemedPageBackground(animated: animated, shootingStars: shootingStars).ignoresSafeArea())
    }
}
