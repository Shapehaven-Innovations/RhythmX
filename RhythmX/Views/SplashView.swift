//  SplashView.swift

import SwiftUI

/// Animated continuation of the launch screen: the dark night scene in every appearance (the launch colours are
/// dark in both, so nothing flashes), a quiet starfield, a soft halo behind the four phase moons, which light up
/// one after another, and the drifting waves.
struct SplashView: View {
    var onFinish: () -> Void

    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = -1

    private let step = 0.55

    var body: some View {
        ZStack {
            NightSceneBackground(animated: !reduceMotion)
            WaveBackground(drift: true)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .frame(height: 300)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: 12) {
                MoonsWithHalo(active: active, size: 34)
                    .padding(.bottom, 12)
                Text("RhythmX")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(Color("LaunchTitle"))
                Text("know your rhythm")
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(Color("LaunchSubtitle"))
            }
            .offset(y: -20)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
        .task {
            if reduceMotion {
                try? await Task.sleep(nanoseconds: 600_000_000)
            } else {
                for i in 0..<Event.EventType.allCases.count {
                    withAnimation(.easeInOut(duration: 0.5)) { active = i }
                    try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            onFinish()
        }
    }
}

/// The four phase moons over a soft moonlit halo; the active one glows.
struct MoonsWithHalo: View {
    let active: Int
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            ForEach(Array(Event.EventType.allCases.enumerated()), id: \.offset) { i, phase in
                MoonPhaseView(phase: phase.moonPhase, color: phase.defaultPhaseColor, isActive: i == active, size: size)
                    .shadow(color: phase.defaultPhaseColor.opacity(i == active ? 0.7 : 0), radius: i == active ? 12 : 0)
                    .opacity(active < 0 || i <= active ? 1 : 0.6)
            }
        }
        .background(
            Circle()
                .fill(RadialGradient(colors: [DS.Color.solid(DS.Theme.current.dark.moon).opacity(0.16), .clear],
                                     center: .center, startRadius: 0, endRadius: 170))
                .frame(width: 340, height: 340)
                .allowsHitTesting(false)
        )
        .accessibilityHidden(true)
    }
}

/// The dark night page of the splash and onboarding: the theme's night page colour, a moonlit halo and the
/// starfield (denser in Eclipse). Twinkles only when `animated`.
struct NightSceneBackground: View {
    var animated: Bool = true

    var body: some View {
        let theme = DS.Theme.current
        let density = AuraPalette.stars(theme: theme, isDark: true)
        let stars = AuraStarField.stars(seed: 21, stars: density)
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !animated)) { timeline in
            ZStack {
                DS.Color.solid(theme.dark.page)
                RadialGradient(colors: [DS.Color.solid(theme.dark.moon).opacity(0.10), .clear],
                               center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 320)
                AuraStarCanvas(stars: stars, moon: DS.Color.solid(theme.dark.moon), opacity: density.opacity,
                               time: animated ? timeline.date.timeIntervalSinceReferenceDate : nil)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    SplashView(onFinish: {}).environmentObject(AppSettings())
}
