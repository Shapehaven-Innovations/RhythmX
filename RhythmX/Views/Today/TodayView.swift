//  TodayView.swift
//  The first tab. The top is the home: date and the sky's moon, the greeting, this week, the breathing moon
//  with the day's headline and main action, the phase line and "My daily insights". Below it, in the same
//  scroll, everything the Insights tab had: the charts and cards per mode and the Doctor Report. The compact
//  mode switcher sits under the week strip so the mode changes without scrolling.

import SwiftUI

struct TodayView: View {
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var fertileStore: FertileStore
    @EnvironmentObject var healthSync: HealthSync
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ambientMotion) private var ambientMotion
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var tileZoom

    /// Screenshots and previews pass a fixed clock and fixed insights; the app uses the real ones.
    var now: Date? = nil
    var fixedInsights: DailyInsights? = nil

    @State private var insights: DailyInsights?
    @State private var tagForm: TagFormRoute?
    @State private var detail: DailyInsightDetailModel?
    /// "Log a Tag" in the pull-up: Add Tag opens once the sheet has gone.
    @State private var addTagAfterDetail = false
    @State private var showAllInsights = false
    @State private var showShare = false
    @State private var showLogPeriod = false
    @State private var periodLogged = 0
    /// Bumped at midnight (and other significant time changes) and when the app becomes active, so the
    /// insights are written again for the new day.
    @State private var clockTick = 0

    private struct TagFormRoute: Identifiable {
        let category: TagCategory?
        var id: String { category?.rawValue ?? "any" }
    }

    // MARK: - Data

    private var today: Date { now ?? Date() }
    private var mode: TrackingMode { appSettings.trackingMode }

    private var snapshot: PhaseWidgetSnapshot {
        PhaseWidgetSnapshot.make(events: myEvents.events, archived: archivedDataStore.archivedBlocks, today: today,
                                 fertileOverrides: fertileStore.overrides)
    }

    var body: some View {
        let snapshot = snapshot
        let menopause = MenopauseInsights.make(events: myEvents.events, today: today)
        let perWeek = menopause.hotFlashesPerWeek
        let hero = TodayHero.make(mode: mode, snapshot: snapshot,
                                  fertileDays: FertileWindow.days(events: myEvents.cycleEvents, overrides: fertileStore.overrides),
                                  hotFlashes: (perWeek.last ?? 0, perWeek.count >= 2 ? perWeek[perWeek.count - 2] : 0),
                                  today: today)
        let palette = AuraPalette.make(phase: mode == .menopause ? nil : snapshot.phase, theme: DS.Theme.current,
                                       isDark: colorScheme == .dark, hour: Calendar.current.component(.hour, from: today))
        let alreadyLogged = mode != .menopause && PeriodStartPlan.alreadyStartedToday(snapshot: snapshot)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(snapshot: snapshot)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.xs)

                    if let greeting = GreetingProvider.text(now: today, style: appSettings.greetingStyle,
                                                            name: appSettings.greetingName) {
                        Text(greeting)
                            .font(.largeTitle.bold())
                            .foregroundColor(DS.Color.primaryText)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, DS.Spacing.md)
                    }

                    TodayWeekStripView(
                        days: TodayWeekStrip.days(events: myEvents.events, today: today, mode: mode,
                                                  nextPeriod: snapshot.nextPeriodDate,
                                                  periodLength: snapshot.averagePeriodLength ?? 5),
                        mode: mode)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.top, 10)

                    // The mode is one tap away at the top of the page, not under Insights.
                    ModeSwitcher(mode: $appSettings.trackingMode, compact: true)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.sm)

                    TodayHeroView(hero: hero, mode: mode, snapshot: snapshot,
                                  menopauseDays: TodayMenopauseWeek.dailyCounts(events: myEvents.events, today: today),
                                  palette: palette,
                                  actionTitle: alreadyLogged ? "Period logged" : nil,
                                  actionDisabled: alreadyLogged) {
                        perform(hero.action)
                    }
                    .padding(.top, DS.Spacing.sm)

                    if let insights {
                        moodLine(insights.moodLine)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.top, DS.Spacing.xs)
                    }

                    tilesSection(snapshot: snapshot, weeks: perWeek)
                        .padding(.top, DS.Spacing.lg)

                    if mode == .planning || hero.isFertilityEstimate {
                        Text(PlanningInsightsView.disclaimer)
                            .font(DS.Font.caption)
                            .foregroundColor(DS.Color.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.top, DS.Spacing.sm)
                    }

                    Text("Insights")
                        .font(.title2.bold())
                        .foregroundColor(DS.Color.primaryText)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.xl)

                    InsightsView()

                    Text(MenopauseInsightsView.disclaimer)
                        .font(DS.Font.caption)
                        .foregroundColor(DS.Color.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, DS.Spacing.lg)
                }
            }
            .scrollIndicators(.hidden)
            .themedPage(animated: true, shootingStars: true)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showShare) { ShareRhythmView() }
        }
        .sheet(item: $tagForm) { route in
            TagFormView(initialCategory: route.category)
        }
        .sheet(item: $detail, onDismiss: {
            if addTagAfterDetail {
                addTagAfterDetail = false
                tagForm = TagFormRoute(category: mode == .cycle ? nil : mode.mainCategory)
            }
        }) { model in
            DailyInsightDetailView(model: model) {
                addTagAfterDetail = true
                detail = nil
            }
            .navigationTransition(.zoom(sourceID: model.tile.id, in: tileZoom))
        }
        .sheet(isPresented: $showAllInsights) {
            if let insights { DailyInsightsListView(insights: insights) }
        }
        // The first day, the length and the consequence live in the shared sheet (also opened from Cycles).
        .sheet(isPresented: $showLogPeriod) {
            LogPeriodSheet(now: now) { periodLogged += 1 }
        }
        .sensoryFeedback(.success, trigger: periodLogged)
        .task(id: insightsKey) { await loadInsights() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            clockTick += 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { clockTick += 1 }
        }
    }

    // MARK: - Header

    private func header(snapshot: PhaseWidgetSnapshot) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            phaseMoons(active: mode == .menopause ? nil : snapshot.phase)
            Text("\(today.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(LunarPhase.of(today).name)")
                .font(.footnote.weight(.semibold))
                .foregroundColor(DS.Color.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Button { showShare = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundColor(DS.Color.primaryText)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Share RhythmX")
            .accessibilityHint("Opens the Share screen")
        }
    }

    /// The four phase moons, the current one lit (as on the launch screen).
    private func phaseMoons(active: Event.EventType?) -> some View {
        HStack(spacing: 4) {
            ForEach(Event.EventType.allCases) { phase in
                MoonPhaseView(phase: phase.moonPhase, color: phase.defaultPhaseColor, isActive: phase == active, size: 16)
                    .opacity(active == nil || phase == active ? 1 : 0.6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(active.map { "Current phase: \($0.displayName)" } ?? "No current phase")
    }

    // MARK: - Mood line

    /// The day's one line from Daily insights; its first sentence in bold, as in the design.
    private func moodLine(_ line: String) -> some View {
        var text = AttributedString(line)
        text.foregroundColor = DS.Color.secondaryText
        if let end = line.range(of: ". ") {
            let first = String(line[..<end.lowerBound]) + "."
            if let range = text.range(of: first) {
                text[range].font = .body.weight(.semibold)
                text[range].foregroundColor = DS.Color.primaryText
            }
        }
        return Text(text)
            .font(.body)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Daily insights

    private func tilesSection(snapshot: PhaseWidgetSnapshot, weeks: [Int]) -> some View {
        let tiles = insights?.tiles ?? []
        let context = DailyInsightTileContext(
            phase: mode == .menopause ? nil : snapshot.phase,
            cycleDay: snapshot.cycleDay,
            fertileToday: snapshot.isFertileToday,
            fertileStartsIn: snapshot.fertileStartsIn,
            hotFlashWeeks: weeks,
            sleepHours: SleepInsights.make(summary: healthSync.importedSleep, today: today).averageHours)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("My daily insights")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(DS.Color.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !tiles.isEmpty {
                    Button("See all") { showAllInsights = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Color.accent)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, DS.Spacing.md)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    ForEach(tiles) { tile in tileButton(tile, context: context, stacked: true) }
                }
                .padding(.horizontal, DS.Spacing.md)
            } else {
                ScrollView(.horizontal) {
                    // One low rate clock floats every tile, and only while `ambientMotion` allows it.
                    TimelineView(.animation(minimumInterval: AmbientMotion.minimumInterval, paused: !ambientMotion)) { timeline in
                        let t = ambientMotion ? timeline.date.timeIntervalSinceReferenceDate : nil
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                                tileButton(tile, context: context, stacked: false)
                                    .offset(y: AmbientMotion.floatOffset(index: index, at: t))
                                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                        content
                                            .offset(y: reduceMotion ? 0 : abs(phase.value) * 6)
                                            .scaleEffect(reduceMotion ? 1 : 1 - abs(phase.value) * 0.04)
                                    }
                            }
                        }
                        .padding(.vertical, DS.Spacing.sm)
                    }
                }
                .contentMargins(.horizontal, DS.Spacing.md, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }

    private func tileButton(_ tile: DailyInsightTile, context: DailyInsightTileContext, stacked: Bool) -> some View {
        Button {
            if tile.kind == .logPrompt {
                tagForm = TagFormRoute(category: mode == .cycle ? nil : mode.mainCategory)
            } else {
                detail = detailModel(for: tile, context: context)
            }
        } label: {
            DailyInsightTileView(tile: tile, context: context, stacked: stacked)
        }
        .buttonStyle(TilePressStyle())
        .matchedTransitionSource(id: tile.id, in: tileZoom)
    }

    /// The pull-up's content for a tile, from the same stores the tile was written from.
    private func detailModel(for tile: DailyInsightTile, context: DailyInsightTileContext) -> DailyInsightDetailModel {
        let facts = InsightFacts.make(events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks,
                                      mode: mode, today: today, fertileOverrides: fertileStore.overrides,
                                      sleepSummary: healthSync.importedSleep)
        return Self.detailModel(tile: tile, mode: mode, events: myEvents.events,
                                archivedBlocks: archivedDataStore.archivedBlocks, insights: insights,
                                facts: facts, snapshot: snapshot, hotFlashWeeks: context.hotFlashWeeks,
                                sharerName: appSettings.sharerName, today: today)
    }

    static func detailModel(tile: DailyInsightTile, mode: TrackingMode, events: [Event], archivedBlocks: [ArchivedDataBlock],
                            insights: DailyInsights?, facts: InsightFacts, snapshot: PhaseWidgetSnapshot,
                            hotFlashWeeks: [Int], sharerName: String, today: Date) -> DailyInsightDetailModel {
        let phase = mode == .menopause ? nil : snapshot.phase
        let cycleBlocks = archivedBlocks.filter { $0.effectiveMode != .menopause }
        let modeEvents = events.filter { ($0.effectiveMode == .menopause) == (mode == .menopause) }
        let modeBlocks = archivedBlocks.filter { ($0.effectiveMode == .menopause) == (mode == .menopause) }
        let choices = QuickLogCardLogic.choices(mode: mode, phase: phase, events: events,
                                                history: TagFormLogic.historyTags(phase: phase, blocks: cycleBlocks),
                                                today: today, limit: InsightDetailContent.maxChips)
        let patternPick = PatternFinder.findings(events: modeEvents, archivedBlocks: modeBlocks, mode: mode, today: today)
            .first { InsightFacts.isSurfaceable(raw: $0.tag) }
            .map { TagFormLogic.pick(fromRaw: $0.tag) }
        let cards = ShareCardModel.cards(for: ShareCardInput(
            mode: mode, insights: insights ?? TemplateInsightWriter().insights(for: facts), facts: facts,
            fertileToday: snapshot.isFertileToday, fertileStartsIn: snapshot.fertileStartsIn, sharerName: sharerName))
        let content = InsightDetailContent.make(
            tile: tile, mode: mode, phase: phase, cycleDay: snapshot.cycleDay,
            cycleLength: snapshot.cycleLength ?? snapshot.averageCycleLength ?? 28, hotFlashWeeks: hotFlashWeeks,
            choices: choices, patternPick: patternPick, shareKinds: Set(cards.map(\.kind)))
        return DailyInsightDetailModel(tile: tile, content: content, facts: facts, mode: mode, phase: phase,
                                       today: today, shareCard: cards.first { $0.kind == content.shareKind })
    }

    // MARK: - Actions

    private func perform(_ action: TodayHero.Action) {
        switch action {
        case .logPeriod:   showLogPeriod = true
        case .logTest:     tagForm = TagFormRoute(category: .planning)
        case .logSymptoms: tagForm = TagFormRoute(category: .menopause)
        }
    }

    // MARK: - Loading

    /// Changes whenever the facts behind the insights could change: the day, the mode, the events, the manual
    /// fertile days, and on every midnight or return to the app (`clockTick`).
    private var insightsKey: String {
        var hasher = Hasher()
        for event in myEvents.events {
            hasher.combine(event.id)
            hasher.combine(event.tags)
            hasher.combine(event.date)
        }
        hasher.combine(archivedDataStore.archivedBlocks.count)
        hasher.combine(healthSync.importedSleep.count)
        hasher.combine(fertileStore.overrides.added.sorted())
        hasher.combine(fertileStore.overrides.removed.sorted())
        let day = Calendar.current.startOfDay(for: today).timeIntervalSince1970
        return "\(mode.rawValue)|\(day)|\(clockTick)|\(hasher.finalize())"
    }

    /// The facts are built off the main actor from value copies of the stores; the result is published here.
    private func loadInsights() async {
        if let fixedInsights { insights = fixedInsights; return }
        let events = myEvents.events
        let blocks = archivedDataStore.archivedBlocks
        let mode = mode
        let today = today
        let overrides = fertileStore.overrides
        let sleep = healthSync.importedSleep
        let (facts, cached) = await Task.detached(priority: .userInitiated) {
            let facts = InsightFacts.make(events: events, archivedBlocks: blocks, mode: mode, today: today,
                                          fertileOverrides: overrides, sleepSummary: sleep)
            return (facts, DailyInsightsService().cachedInsights(for: facts))
        }.value
        guard !Task.isCancelled else { return }
        if let cached {
            insights = cached
            return
        }
        // The template shows at once; the on-device text replaces it when it is ready.
        insights = TemplateInsightWriter().insights(for: facts)
        let written = await DailyInsightsService().insights(for: facts)
        guard !Task.isCancelled else { return }
        insights = written
    }
}

/// A gentle press for the tiles.
private struct TilePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25), value: configuration.isPressed)
    }
}

#Preview {
    TodayView()
        .environmentObject(EventStore(preview: true))
        .environmentObject(ArchivedDataStore())
        .environmentObject(AppSettings())
        .environmentObject(FertileStore())
        .environmentObject(HealthSync())
}
