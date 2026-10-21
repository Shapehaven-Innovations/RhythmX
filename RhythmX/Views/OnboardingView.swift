//  OnboardingView.swift
//  Five short pages, every one skippable: the welcome on the dark moon screen (with Restore from a Backup),
//  what you track (sets the mode), an optional last period start, the four phases, and the greeting with a
//  permissions primer. Nothing asks iOS for anything until the person taps, and nothing here removes or
//  replaces existing entries (`OnboardingPeriodStart`). Settings > Replay welcome shows it again; finishing a
//  replay only closes it.

import SwiftUI

struct OnboardingView: View {
    /// Opened from Settings: no restore, and finishing calls `onFinish` instead of ending first run.
    var isReplay: Bool = false
    var onFinish: () -> Void = {}
    /// Screenshots open a given page with the intro already played.
    var initialPage: OnboardingPage = .welcome
    var now: Date? = nil

    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var purchaseStore: PurchaseStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @AppStorage("selectedTab") private var selectedTab = 0

    @State private var page: OnboardingPage = .welcome
    @State private var forward = true
    @State private var periodDate = Date()
    @State private var periodChosen = false
    @State private var primer = OnboardingPrimer()
    @State private var showImporter = false
    @State private var incoming: IncomingBackup?
    @State private var finishTick = 0
    @AccessibilityFocusState private var titleFocused: Bool

    private var today: Date { now ?? Date() }
    private var mode: TrackingMode { appSettings.trackingMode }

    init(isReplay: Bool = false, onFinish: @escaping () -> Void = {}, initialPage: OnboardingPage = .welcome, now: Date? = nil) {
        self.isReplay = isReplay
        self.onFinish = onFinish
        self.initialPage = initialPage
        self.now = now
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        let dark = page == .welcome
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                ZStack {
                    pageView(page)
                        .id(page)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomButtons
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.md)
            }
        }
        .environment(\.colorScheme, dark ? .dark : systemScheme)
        .preferredColorScheme(dark ? .dark : nil)
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            if value.translation.width < -60, let next = page.next(for: mode) { go(to: next) }
            if value.translation.width > 60, let previous = page.previous(for: mode) { go(to: previous) }
        })
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.success, trigger: finishTick)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.rhythmxBackup]) { result in
            if case .success(let url) = result { incoming = IncomingBackup(url: url) }
        }
        .sheet(item: $incoming) { item in
            RestoreSheet(url: item.url)
                .environmentObject(myEvents)
                .environmentObject(archivedDataStore)
                .environmentObject(appSettings)
        }
        .onAppear {
            if appSettings.dailyInsightsOn { primer.set(.dailyInsights, .on) }
            if appSettings.healthWritePeriod || appSettings.healthReadTemperature || appSettings.healthReadSleep {
                primer.set(.appleHealth, .on)
            }
            if appSettings.calendarSyncOn && purchaseStore.isPlus { primer.set(.appleCalendar, .on) }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if page == .welcome {
            ZStack(alignment: .bottom) {
                NightSceneBackground(animated: !reduceMotion)
                WaveBackground(drift: true)
                    .frame(height: 300)
            }
            .ignoresSafeArea()
            .transition(.opacity)
        } else {
            ThemedPageBackground()
                .environment(\.auraPhase, page == .phases ? .ovulation : .luteal)
                .ignoresSafeArea()
                .transition(.opacity)
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func pageView(_ page: OnboardingPage) -> some View {
        switch page {
        case .welcome:
            OnboardingWelcomePage(animateIntro: initialPage == .welcome && now == nil, titleFocused: $titleFocused)
        case .mode:
            OnboardingModePage(mode: $appSettings.trackingMode, titleFocused: $titleFocused)
        case .lastPeriod:
            OnboardingPeriodPage(date: $periodDate, chosen: $periodChosen,
                                 range: OnboardingPeriodStart.pickerRange(today: today),
                                 hasCycleData: OnboardingPeriodStart.hasCycleData(myEvents.events),
                                 titleFocused: $titleFocused)
        case .phases:
            OnboardingPhasesPage(titleFocused: $titleFocused)
        case .makeItYours:
            OnboardingMakeItYoursPage(primer: $primer, now: today, isPlus: purchaseStore.isPlus,
                                      previewInsights: previewInsights,
                                      titleFocused: $titleFocused, enable: enable, later: { primer.set($0, .later) },
                                      confirmDailyInsights: confirmDailyInsights)
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private func go(to target: OnboardingPage) {
        forward = target.rawValue > page.rawValue
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { page = target }
        } else {
            withAnimation(.spring(duration: 0.45, bounce: 0.12)) { page = target }
        }
        titleFocused = true
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            if page.showsBack, let previous = page.previous(for: mode) {
                Button { go(to: previous) } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(DS.Color.primaryText)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Back")
            }
            HStack(spacing: 6) {
                ForEach(OnboardingPage.pages(for: mode)) { dot in
                    Capsule()
                        .fill(dot.rawValue <= page.rawValue ? DS.Color.accent : DS.Color.primaryText.opacity(0.2))
                        .frame(width: dot == page ? 22 : 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(page.accessibilityPosition(for: mode))
            Spacer()
            if page.showsSkip {
                Button("Skip") { finish() }
                    .font(.body.weight(.semibold))
                    .foregroundColor(DS.Color.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint(isReplay ? "Closes the welcome" : "Starts RhythmX now; you can set things up later in Settings")
            }
        }
        .frame(minHeight: 44)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: page)
    }

    // MARK: - Bottom

    private var bottomButtons: some View {
        VStack(spacing: DS.Spacing.sm) {
            OnboardingCapsuleButton(title: page.primaryTitle(replay: isReplay), style: .primary) { primaryTapped() }
            switch page {
            case .welcome where !isReplay:
                OnboardingCapsuleButton(title: "Restore from a Backup", style: .onNight) { showImporter = true }
                    .accessibilityHint("Opens Files to choose a RhythmX backup")
            case .lastPeriod where !OnboardingPeriodStart.hasCycleData(myEvents.events):
                OnboardingCapsuleButton(title: "I am not sure", style: .plain) {
                    periodChosen = false
                    go(to: .phases)
                }
            default:
                EmptyView()
            }
        }
    }

    private func primaryTapped() {
        if page == .lastPeriod, let plan = OnboardingPeriodStart.continuePlan(events: myEvents.events, start: periodDate,
                                                                              chosen: periodChosen, mode: mode, today: today) {
            // Continue logs a date only when the person chose one (the default today, I am not sure and Skip
            // log nothing), through the Log Period plan; on a phone with no cycle data there is nothing to archive.
            if !plan.archive.isEmpty {
                _ = archivedDataStore.archiveCurrent(events: plan.archive, mode: appSettings.trackingMode == .planning ? .planning : .cycle)
            }
            myEvents.replaceAll(plan.events)
            myEvents.reloadCalendarIcons()
            periodChosen = false
        }
        if let next = page.next(for: mode) { go(to: next) } else { finish() }
    }

    private func finish() {
        finishTick += 1
        if primer.opensSettingsOnFinish { selectedTab = 4 }
        AppGroup.reloadWidgets()
        if isReplay {
            onFinish()
        } else {
            didFinishOnboarding = true
        }
    }

    // MARK: - Primer

    /// Today's template note, for the Lock Screen preview in the primer.
    private var previewInsights: DailyInsights {
        TemplateInsightWriter().insights(for: InsightFacts.make(events: myEvents.events,
                                                                archivedBlocks: archivedDataStore.archivedBlocks,
                                                                mode: mode, today: today))
    }

    /// Runs the item's own flow at this moment. Daily insights first shows the Lock Screen choice; nothing asks
    /// iOS or schedules until that is confirmed (`confirmDailyInsights`).
    private func enable(_ item: OnboardingPrimer.Item) {
        switch item.enableAction(isPlus: purchaseStore.isPlus) {
        case .chooseLockScreenPrivacy:
            primer.set(item, .choosingPrivacy)
        case .requestNotifications:
            confirmDailyInsights()
        case .showInSettings:
            primer.set(item, .inSettings)
        case .explainPlus:
            primer.set(item, .plusNeeded)
        }
    }

    /// The Lock Screen choice is saved first, so the very first note already follows it; then iOS is asked.
    private func confirmDailyInsights() {
        appSettings.dailyInsightsDiscreet = primer.lockScreenChoice.discreet
        NotificationScheduler.requestPermissionIfNeeded { granted in
            if granted {
                appSettings.dailyInsightsOn = true
                DailyInsightsCoordinator.shared.update(write: true)
                primer.set(.dailyInsights, .on)
            } else {
                primer.set(.dailyInsights, .denied)
            }
        }
    }
}

// MARK: - Button

struct OnboardingCapsuleButton: View {
    enum Style { case primary, onNight, plain }
    let title: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(foreground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.vertical, 2)
                .background {
                    switch style {
                    case .primary:
                        Capsule().fill(DS.Color.accent)
                    case .onNight:
                        Capsule().fill(Color(red: 10 / 255, green: 6 / 255, blue: 14 / 255).opacity(0.42))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    case .plain:
                        Color.clear
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(OnboardingPressStyle())
    }

    private var foreground: Color {
        switch style {
        case .primary: return DS.Color.onAccent
        case .onNight: return .white
        case .plain:   return DS.Color.accent
        }
    }
}

private struct OnboardingPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25), value: configuration.isPressed)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(EventStore(preview: true))
        .environmentObject(ArchivedDataStore())
        .environmentObject(AppSettings())
        .environmentObject(PurchaseStore(listensForUpdates: false))
}
