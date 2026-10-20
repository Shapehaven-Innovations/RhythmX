//  OnboardingView.swift

import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var appSettings: AppSettings
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @State private var page = 0
    @State private var startDate = Date()
    @State private var cycleLength = 28

    var body: some View {
        ZStack(alignment: .bottom) {
            ThemedPageBackground().ignoresSafeArea()
            TabView(selection: $page) {
                welcomePage.tag(0)
                privacyPage.tag(1)
                setupPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            controls
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        ZStack(alignment: .bottom) {
            WaveBackground(drift: true).frame(height: 360).ignoresSafeArea(edges: .bottom)
            VStack(spacing: DS.Spacing.lg) {
                Spacer()
                MoonRow()
                Text("Know your rhythm.")
                    .font(DS.Font.displayTitle)
                    .multilineTextAlignment(.center)
                    .foregroundColor(DS.Color.primaryText)
                Text("Track your cycle, notice your patterns, and keep it all to yourself.")
                    .font(DS.Font.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(DS.Color.secondaryText)
                    .padding(.horizontal, DS.Spacing.xl)
                Spacer()
                Spacer()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var privacyPage: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()
            MoonPhaseView(phase: .full, color: DS.Color.moon, isActive: true, size: 56)
            Text("Private by design.")
                .font(DS.Font.displayTitle)
                .foregroundColor(DS.Color.primaryText)
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                promise("Stored only on this device")
                promise("No account or sign-in")
                promise("No ads, no tracking, no analytics")
                promise("Shared only when you choose to")
            }
            .cardStyle()
            .padding(.horizontal, DS.Spacing.md)
            Spacer()
            Spacer()
        }
    }

    private var setupPage: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            Text("Set up your first cycle.")
                .font(DS.Font.displayTitle)
                .multilineTextAlignment(.center)
                .foregroundColor(DS.Color.primaryText)
            Text("You can change this any time in Cycles.")
                .font(DS.Font.label)
                .foregroundColor(DS.Color.secondaryText)
            VStack(spacing: DS.Spacing.sm) {
                DatePicker("First day of cycle", selection: $startDate, in: ...Date(), displayedComponents: .date)
                Stepper(value: $cycleLength, in: 20...40) { Text("Cycle length: \(cycleLength) days") }
                PhaseStrip(segments: Event.EventType.allCases.map { ($0, CycleGenerator.dayCounts(cycleLength: cycleLength)[$0] ?? 0) })
                    .padding(.top, DS.Spacing.xs)
            }
            .cardStyle()
            .padding(.horizontal, DS.Spacing.md)
            Spacer()
            Spacer()
        }
    }

    private func promise(_ text: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(DS.Color.accent)
            Text(text).font(DS.Font.label).foregroundColor(DS.Color.primaryText)
        }
    }

    // MARK: - Controls

    /// Page 1 sits over the waves, so Skip uses the theme's on-wave colour instead of SecondaryButton
    /// (white on Blush; on a Plus theme the colour that reads on its accent, which the waves come from).
    private var onWaveSkip: some View {
        Button { didFinishOnboarding = true } label: {
            Text("Skip")
                .font(DS.Font.label.weight(.semibold))
                .foregroundColor(DS.Color.onWave)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.button)
                        .stroke(DS.Color.onWave, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Skip")
    }

    private var controls: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(i == page ? DS.Color.accent : DS.Color.separator)
                        .frame(width: i == page ? 16 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            if page < 2 {
                PrimaryButton(title: "Continue") { if reduceMotion { page += 1 } else { withAnimation { page += 1 } } }
                if page == 0 {
                    onWaveSkip
                } else {
                    SecondaryButton(title: "Skip") { didFinishOnboarding = true }
                }
            } else {
                PrimaryButton(title: "Start tracking") {
                    // Skipped when a restore already brought events in.
                    myEvents.generateInitialCycleEventsIfEmpty(startDate: startDate, cycleLength: cycleLength)
                    didFinishOnboarding = true
                }
                SecondaryButton(title: "Set up later") { didFinishOnboarding = true }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.md)
    }
}

/// The four phase moons with a glow that travels across them.
private struct MoonRow: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = 2
    private let timer = Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            ForEach(Array(Event.EventType.allCases.enumerated()), id: \.offset) { i, phase in
                MoonPhaseView(phase: phase.moonPhase,
                              color: appSettings.phaseColor(for: phase),
                              isActive: i == active, size: 34)
            }
        }
        .onReceive(timer) { _ in
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8)) { active = (active + 1) % 4 }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(EventStore(preview: true))
        .environmentObject(AppSettings())
}
