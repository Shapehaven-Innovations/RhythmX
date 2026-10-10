//  SplashView.swift

import SwiftUI

/// Animated continuation of the static launch screen: waves drift and the four phase moons light up once.
struct SplashView: View {
    var onFinish: () -> Void

    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = -1

    private let step = 0.55

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            WaveBackground(drift: true)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .frame(height: 300)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: 12) {
                HStack(spacing: DS.Spacing.lg) {
                    ForEach(Array(Event.EventType.allCases.enumerated()), id: \.offset) { i, phase in
                        MoonPhaseView(phase: phase.moonPhase,
                                      color: appSettings.phaseColor(for: phase),
                                      isActive: i == active, size: 34)
                    }
                }
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

#Preview {
    SplashView(onFinish: {}).environmentObject(AppSettings())
}
