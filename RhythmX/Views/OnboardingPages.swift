//  OnboardingPages.swift
//  The five onboarding pages and their art. Each page scrolls, so every text size fits; the art steps back
//  at accessibility sizes.

import SwiftUI

// MARK: - Shared

private struct OnboardingTitle: View {
    let page: OnboardingPage
    var titleFocused: AccessibilityFocusState<Bool>.Binding
    var color: Color = DS.Color.primaryText
    var alignment: TextAlignment = .leading

    var body: some View {
        Text(page.title)
            .font(.largeTitle.bold())
            .foregroundColor(color)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused(titleFocused)
    }
}

private struct PageScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// A moon in moon colour: `lit` 1 is full, 0.5 half, 0 new; `waxing` lights the right side.
struct OnboardingMoon: View {
    let lit: Double
    var waxing: Bool = true
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(DS.Color.primaryText.opacity(0.1))
            Circle()
                .fill(DS.Color.moon)
                .mask {
                    ZStack {
                        Rectangle()
                        Circle()
                            .offset(x: (waxing ? -1 : 1) * size * lit)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct Glint: View {
    let size: CGFloat
    var body: some View {
        Canvas { ctx, canvasSize in
            ctx.fill(AuraStarCanvas.glint(x: canvasSize.width / 2, y: canvasSize.height / 2, size: size),
                     with: .color(DS.Color.moon.opacity(0.7)))
        }
        .frame(width: size * 3, height: size * 3)
        .accessibilityHidden(true)
    }
}

// MARK: - 1. Welcome

struct OnboardingWelcomePage: View {
    /// Plays the bloom: the icon rises, the four moons light in order, the title rises.
    let animateIntro: Bool
    var titleFocused: AccessibilityFocusState<Bool>.Binding

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var stage = 3
    @State private var activeMoon = 3

    var body: some View {
        PageScroll {
            VStack(spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [DS.Color.accent.opacity(0.45), .clear],
                                                 center: .center, startRadius: 0, endRadius: 80))
                            .frame(width: 160, height: 160)
                            .opacity(stage >= 1 ? 1 : 0)
                        Image("ExportLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 92, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                            .shadow(color: .black.opacity(0.6), radius: 20, y: 18)
                            .scaleEffect([0.86, 0.96, 1.02, 1][stage])
                            .opacity([0.3, 0.8, 1, 1][stage])
                    }
                    .padding(.top, [86.0, 74, 56, 56][stage])
                    .accessibilityHidden(true)
                }
                MoonsWithHalo(active: activeMoon, size: 34)
                    .padding(.top, 34)
                VStack(spacing: 12) {
                    OnboardingTitle(page: .welcome, titleFocused: titleFocused, color: Color("LaunchTitle"), alignment: .center)
                    Text(OnboardingPage.welcome.body ?? "")
                        .font(.body)
                        .foregroundColor(Color("LaunchSubtitle"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 26)
                .offset(y: [16.0, 8, 0, 0][stage])
                .opacity([0.0, 0.6, 1, 1][stage])
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            guard animateIntro, !reduceMotion else { return }
            stage = 0
            activeMoon = 0
            for step in 1...3 {
                try? await Task.sleep(for: .milliseconds(420))
                withAnimation(.spring(duration: 0.6, bounce: 0.2)) {
                    stage = step
                    activeMoon = step
                }
            }
        }
    }
}

// MARK: - 2. Mode

struct OnboardingModePage: View {
    @Binding var mode: TrackingMode
    var titleFocused: AccessibilityFocusState<Bool>.Binding
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PageScroll {
            if !dynamicTypeSize.isAccessibilitySize {
                ZStack {
                    HStack(spacing: -8) {
                        OnboardingMoon(lit: 0.22, waxing: true, size: 60)
                        OnboardingMoon(lit: 1, size: 92).zIndex(1)
                        OnboardingMoon(lit: 0.22, waxing: false, size: 60)
                    }
                    Glint(size: 5).offset(x: -120, y: -50)
                    Glint(size: 4).offset(x: 130, y: 50)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 170)
            }
            OnboardingTitle(page: .mode, titleFocused: titleFocused)
                .padding(.top, DS.Spacing.md)
            VStack(spacing: 10) {
                option(.cycle, subtitle: "Periods, phases and how you feel")
                option(.planning, subtitle: "Fertile window, tests and temperature")
                option(.menopause, subtitle: "Hot flashes, sleep and symptoms")
            }
            .padding(.top, DS.Spacing.md)
            Text(OnboardingPage.mode.body ?? "")
                .font(.footnote)
                .foregroundColor(DS.Color.secondaryText)
                .padding(.top, 10)
        }
    }

    private func option(_ candidate: TrackingMode, subtitle: String) -> some View {
        let selected = candidate == mode
        return Button {
            if reduceMotion { mode = candidate } else { withAnimation(.spring(duration: 0.3)) { mode = candidate } }
        } label: {
            HStack(spacing: 14) {
                icon(candidate)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(DS.Color.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title).font(.headline).foregroundColor(DS.Color.primaryText)
                    Text(subtitle).font(.subheadline).foregroundColor(DS.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                ZStack {
                    Circle().strokeBorder(DS.Color.separator, lineWidth: 1.8).opacity(selected ? 0 : 1)
                    if selected {
                        Circle().fill(DS.Color.accent)
                        Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundColor(DS.Color.onAccent)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(CardSurface(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(DS.Color.accent, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func icon(_ mode: TrackingMode) -> some View {
        switch mode {
        case .cycle:
            ZStack {
                ForEach(Array(Event.EventType.allCases.enumerated()), id: \.offset) { i, phase in
                    Circle()
                        .trim(from: Double(i) / 4 + 0.02, to: Double(i + 1) / 4 - 0.02)
                        .stroke(phase.defaultPhaseColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 26, height: 26)
        case .planning:
            Image(systemName: "testtube.2").font(.title3).foregroundColor(DS.Color.accent)
        case .menopause:
            Image(systemName: "flame").font(.title3).foregroundColor(DS.Color.accent)
        }
    }
}

// MARK: - 3. Last period

struct OnboardingPeriodPage: View {
    @Binding var date: Date
    @Binding var chosen: Bool
    let range: ClosedRange<Date>
    let hasCycleData: Bool
    var titleFocused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        PageScroll {
            Group {
                if hasCycleData {
                    HStack(alignment: .top, spacing: 12) {
                        MoonPhaseView(phase: .full, color: DS.Color.phase1, size: 34)
                        Text("Your cycles are already here. When a new period starts, use Log Period on Today.")
                            .font(.body)
                            .foregroundColor(DS.Color.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    DatePicker("Last period start", selection: Binding(get: { date }, set: { date = $0; chosen = true }),
                               in: range, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(DS.Color.phase1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .accessibilityHint("Optional. Choose the first day of your last period.")
                }
            }
            .background(CardSurface(cornerRadius: 30))
            .padding(.top, DS.Spacing.lg)

            OnboardingTitle(page: .lastPeriod, titleFocused: titleFocused)
                .padding(.top, DS.Spacing.lg)
            Text(chosen && !hasCycleData
                 ? "Started \(date.formatted(.dateTime.weekday(.wide).month(.wide).day())). Continue logs it; I am not sure skips it."
                 : (OnboardingPage.lastPeriod.body ?? ""))
                .font(.body)
                .foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }
}

// MARK: - 4. Phases

struct OnboardingPhasesPage: View {
    var titleFocused: AccessibilityFocusState<Bool>.Binding
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = 4

    static let powers: [(Event.EventType, String)] = [
        (.menstrual, "Rest and renew."), (.follicular, "Rising energy."),
        (.ovulation, "Full bloom."), (.luteal, "Turn inward."),
    ]

    var body: some View {
        PageScroll {
            if !dynamicTypeSize.isAccessibilitySize {
                PhaseCycleArt(lit: lit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 270)
                    .padding(.top, DS.Spacing.sm)
            }
            OnboardingTitle(page: .phases, titleFocused: titleFocused)
                .padding(.top, DS.Spacing.md)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.powers, id: \.0) { phase, power in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        MoonPhaseView(phase: phase.moonPhase, color: phase.defaultPhaseColor, size: 18)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                        (Text(power).bold().foregroundColor(phase.defaultPhaseColor)
                         + Text(" " + phase.rawValue.capitalized).foregroundColor(DS.Color.secondaryText))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, DS.Spacing.md)
            Text(OnboardingPage.phases.body ?? "")
                .font(.subheadline)
                .foregroundColor(DS.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Spacing.md)
            Text(InsightDetailContent.fertilityFooter)
                .font(.footnote)
                .foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Spacing.sm)
        }
        .task {
            guard !reduceMotion else { return }
            lit = 0
            for step in 1...4 {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeOut(duration: 0.5)) { lit = step }
            }
        }
    }
}

/// A cycle drawn as four arcs in the phase colours with numbered badges and a moonlit centre. `lit` arcs are
/// drawn (they light up in order on arrival).
struct PhaseCycleArt: View {
    let lit: Int

    var body: some View {
        let counts = CycleGenerator.dayCounts(cycleLength: 28)
        let phases = Event.EventType.allCases
        let total = Double(phases.reduce(0) { $0 + (counts[$1] ?? 0) })
        var starts: [Double] = []
        var cursor = 0.0
        for phase in phases {
            starts.append(cursor)
            cursor += Double(counts[phase] ?? 0) / total
        }
        let size: CGFloat = 250
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [DS.Color.moon.opacity(0.5), DS.Color.cardBackground],
                                     center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: 140))
                .frame(width: 200, height: 200)
                .shadow(color: DS.Color.moon.opacity(0.4), radius: 25)
            ForEach(Array(phases.enumerated()), id: \.offset) { i, phase in
                let end = (i + 1 < phases.count ? starts[i + 1] : 1) - 0.008
                Circle()
                    .trim(from: starts[i] + 0.008, to: i < lit ? end : starts[i] + 0.008)
                    .stroke(phase.defaultPhaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size - 8, height: size - 8)
                let angle = (starts[i] + 0.04) * 2 * .pi - .pi / 2
                Text("\(i + 1)")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(phase.defaultPhaseColor))
                    .offset(x: cos(angle) * (size / 2 - 4) * 0.82, y: sin(angle) * (size / 2 - 4) * 0.82)
                    .opacity(i < lit ? 1 : 0.3)
            }
            VStack(spacing: 2) {
                Text("A CYCLE").font(.caption.weight(.bold)).tracking(2).foregroundColor(DS.Color.accent)
                Text("Four phases").font(.title2.bold()).foregroundColor(DS.Color.primaryText)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 5. Make it yours

struct OnboardingMakeItYoursPage: View {
    @Binding var primer: OnboardingPrimer
    let now: Date
    let isPlus: Bool
    var previewInsights: DailyInsights? = nil
    var titleFocused: AccessibilityFocusState<Bool>.Binding
    let enable: (OnboardingPrimer.Item) -> Void
    let later: (OnboardingPrimer.Item) -> Void
    var confirmDailyInsights: () -> Void = {}

    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        PageScroll {
            if !dynamicTypeSize.isAccessibilitySize {
                ZStack {
                    HStack(spacing: -6) {
                        OnboardingMoon(lit: 0.4, waxing: true, size: 44)
                        OnboardingMoon(lit: 1, size: 68).zIndex(1)
                        OnboardingMoon(lit: 0.4, waxing: false, size: 44)
                    }
                    Glint(size: 5).offset(x: -100, y: -26)
                    Glint(size: 4).offset(x: 110, y: 30)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 104)
            }
            OnboardingTitle(page: .makeItYours, titleFocused: titleFocused)
                .padding(.top, DS.Spacing.sm)
            greetingCard
                .padding(.top, DS.Spacing.md)
            primerCard
                .padding(.top, 12)
            Text(OnboardingPage.makeItYours.body ?? "")
                .font(.footnote)
                .foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private var greetingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Greeting on Today").font(.footnote.weight(.semibold)).foregroundColor(DS.Color.secondaryText)
            Text(GreetingProvider.text(now: now, style: appSettings.greetingStyle, name: appSettings.greetingName) ?? "No greeting")
                .font(.title2.weight(.semibold))
                .foregroundColor(DS.Color.primaryText)
                .accessibilityLabel("Today shows: \(GreetingProvider.text(now: now, style: appSettings.greetingStyle, name: appSettings.greetingName) ?? "no greeting")")
            Picker("Greeting", selection: $appSettings.greetingStyle) {
                Text("Time of day").tag(GreetingStyle.greeting)
                Text("With my name").tag(GreetingStyle.name)
                Text("Off").tag(GreetingStyle.off)
            }
            .pickerStyle(.segmented)
            if appSettings.greetingStyle == .name {
                TextField("Your name", text: $appSettings.greetingName)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                CardSurface(cornerRadius: 26)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(RadialGradient(colors: [DS.Color.moon.opacity(0.4), .clear],
                                         center: .topTrailing, startRadius: 0, endRadius: 220))
            }
        )
        .sensoryFeedback(.selection, trigger: appSettings.greetingStyleRaw)
    }

    private var primerCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(OnboardingPrimer.Item.allCases.enumerated()), id: \.element) { index, item in
                if index > 0 { Divider().padding(.leading, 60) }
                primerRow(item)
                if item == .dailyInsights && primer.state(item) == .choosingPrivacy {
                    lockScreenChooser
                }
            }
        }
        .background(CardSurface(cornerRadius: 26))
    }

    /// Shown after Enable on Daily insights, before anything is scheduled: what the Lock Screen will show, and
    /// the choice between details and private (private is picked to start with).
    private var lockScreenChooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let previewInsights {
                let preview = OnboardingPrimer.preview(previewInsights, choice: primer.lockScreenChoice)
                HStack(alignment: .top, spacing: 10) {
                    Image("ExportLogo")
                        .resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preview.title).fontWeight(.semibold)
                        Text(preview.body).opacity(0.9).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .font(.footnote)
                .foregroundColor(.white)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 27 / 255, green: 19 / 255, blue: 40 / 255)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Lock Screen preview: \(preview.title). \(preview.body)")
            }
            ForEach(OnboardingPrimer.LockScreenChoice.allCases) { choice in
                Button {
                    primer.lockScreenChoice = choice
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: primer.lockScreenChoice == choice ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(DS.Color.accent)
                            .accessibilityHidden(true)
                        Text(choice.title).font(.subheadline).foregroundColor(DS.Color.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(primer.lockScreenChoice == choice ? .isSelected : [])
            }
            Text("This covers every RhythmX notification. You can change it in Settings, Notifications.")
                .font(.caption)
                .foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Later") { later(.dailyInsights) }
                    .font(.subheadline)
                    .foregroundColor(DS.Color.secondaryText)
                    .frame(minHeight: 44)
                Spacer()
                Button(OnboardingPrimer.Item.dailyInsights.enableTitle) { confirmDailyInsights() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Color.onAccent)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(DS.Color.accent))
                    .accessibilityHint("Asks iOS to allow notifications for Daily insights")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .sensoryFeedback(.selection, trigger: primer.lockScreenChoice)
    }

    private func iconColor(_ item: OnboardingPrimer.Item) -> Color {
        switch item {
        case .dailyInsights: return DS.Color.phase4
        case .appleHealth:   return Color(red: 1, green: 55 / 255, blue: 95 / 255)
        case .appleCalendar: return DS.Color.phase2
        }
    }

    private func primerRow(_ item: OnboardingPrimer.Item) -> some View {
        let state = primer.state(item)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(iconColor(item)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title).font(.body).foregroundColor(DS.Color.primaryText)
                        if item == .appleCalendar && !isPlus {
                            Text("Plus")
                                .font(.caption2.weight(.semibold)).foregroundColor(DS.Color.accent)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(DS.Color.accent.opacity(0.14)))
                        }
                    }
                    Text(item.detail(for: state) ?? item.reason)
                        .font(.footnote)
                        .foregroundColor(state == .denied ? .orange : DS.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            if state == .idle {
                VStack(spacing: 2) {
                    Button(item.enableTitle) { enable(item) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Color.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(DS.Color.accent.opacity(0.12)))
                        .accessibilityLabel("\(item.enableTitle), \(item.title)")
                    Button("Later") { later(item) }
                        .font(.caption)
                        .foregroundColor(DS.Color.secondaryText)
                        .frame(minHeight: 28)
                        .accessibilityLabel("Later, \(item.title)")
                }
            } else if state == .on {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(DS.Color.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .animation(.easeInOut(duration: 0.2), value: state)
    }
}
