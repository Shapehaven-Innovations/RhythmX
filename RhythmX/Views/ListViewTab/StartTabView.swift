//  StartTabView.swift

import SwiftUI
import Combine

struct StartTabView: View {
    @AppStorage("selectedTab") private var selection = 0
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var fertileStore: FertileStore
    @EnvironmentObject var purchaseStore: PurchaseStore

    /// A notification tap asked for the tag form on this category.
    @State private var tagFormRequest: TagFormRequest?
    /// A Daily insights tap asked for the quick log card.
    @State private var quickLogRoute: QuickLogRoute?
    /// "More tags" on the quick log card: the full Add Tags sheet opens on this category once the card is closed.
    @State private var moreTagsCategory: TagCategory?
    /// Tags | Patterns on the Tags tab; the weekly check-in tap selects Patterns.
    @State private var tagsSegment: TagsSegment = .tags

    private struct TagFormRequest: Identifiable {
        let category: TagCategory
        var id: String { category.rawValue }
    }

    private var persistenceErrorMessage: String? {
        myEvents.persistenceError ?? archivedDataStore.persistenceError
    }

    /// The theme that is actually drawn (a Plus theme falls back to Blush without Plus). Colours come from
    /// `DS.Color` on every read, and a child view whose inputs did not change is not redrawn, so the tabs
    /// get this as their identity: a theme or entitlement change rebuilds them with the new colours.
    /// Settings is left out so the theme picker keeps its scroll position; the tab selection is stored
    /// above these views and survives. `purchaseStore.isPlus` is read so a lapse also redraws.
    private var themeIdentity: String {
        _ = purchaseStore.isPlus
        return DS.Theme.current.id
    }

    /// The phase the page backgrounds are tinted with: today's cycle phase, or nil in Menopause mode. Worked
    /// out once per change (`refreshAuraPhase`), not on every body pass.
    @State private var auraPhase: Event.EventType?
    @Environment(\.scenePhase) private var scenePhase

    /// `@Published` publishers send the new value before the store holds it, so the handlers pass it in.
    private func refreshAuraPhase(events: [Event]? = nil, archived: [ArchivedDataBlock]? = nil,
                                  overrides: FertileOverrides? = nil) {
        let phase = Self.auraPhase(mode: appSettings.trackingMode, events: events ?? myEvents.events,
                                   archived: archived ?? archivedDataStore.archivedBlocks,
                                   overrides: overrides ?? fertileStore.overrides, today: Date())
        if phase != auraPhase { auraPhase = phase }
    }

    static func auraPhase(mode: TrackingMode, events: [Event], archived: [ArchivedDataBlock],
                          overrides: FertileOverrides, today: Date) -> Event.EventType? {
        guard mode != .menopause else { return nil }
        return PhaseWidgetSnapshot.make(events: events, archived: archived, today: today, fertileOverrides: overrides).phase
    }

    var body: some View {
        let themeIdentity = themeIdentity
        TabView(selection: $selection) {
            TodayView()
                .ambientMotionScope()
                .id(themeIdentity)
                .tabItem { Label("Today", systemImage: "moonphase.first.quarter") }
                .tag(0)

            EventsCalendarView()
                .id(themeIdentity)
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(1)

            EventsListView(segment: $tagsSegment)
                .id(themeIdentity)
                .tabItem { Label("Tags", systemImage: "tag.fill") }
                .tag(2)

            SettingsCycleInfoView()
                .id(themeIdentity)
                .tabItem { Label("Cycles", systemImage: "moon.circle") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        // The system Liquid Glass tab bar, tinted with the theme accent.
        .tint(DS.Color.accent)
        // Every page's living background follows the current phase (none in Menopause).
        .environment(\.auraPhase, auraPhase)
        .onAppear { refreshAuraPhase() }
        .onReceive(myEvents.$events.dropFirst()) { refreshAuraPhase(events: $0) }
        .onReceive(archivedDataStore.$archivedBlocks.dropFirst()) { refreshAuraPhase(archived: $0) }
        .onReceive(fertileStore.$overrides.dropFirst()) { refreshAuraPhase(overrides: $0) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshAuraPhase()
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshAuraPhase() } }
        .onChange(of: appSettings.themeID) { _, _ in AppGroup.reloadWidgets() }
        .alert("Data Error", isPresented: Binding(
            get: { persistenceErrorMessage != nil },
            set: { if !$0 {
                myEvents.persistenceError = nil
                archivedDataStore.persistenceError = nil
            }}
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceErrorMessage ?? "")
        }
        // Notification taps (NotificationTapRouter): the quick log (Daily insights), the tag form on a category,
        // or Patterns on the Tags tab.
        // A tap that launched the app was posted before this view existed, so it is also read on appear.
        .onAppear(perform: consumePendingTap)
        .onReceive(NotificationCenter.default.publisher(for: .rhythmxOpenTagForm)) { note in
            _ = NotificationTapRouter.shared.takePendingRoute()
            openTagForm(categoryRaw: note.userInfo?["category"] as? String)
        }
        .onReceive(NotificationCenter.default.publisher(for: .rhythmxOpenPatterns)) { _ in
            _ = NotificationTapRouter.shared.takePendingRoute()
            openPatterns()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rhythmxOpenQuickLog)) { _ in
            _ = NotificationTapRouter.shared.takePendingRoute()
            openQuickLog()
        }
        .sheet(item: $tagFormRequest) { request in
            TagFormView(initialCategory: request.category)
        }
        .sheet(item: $quickLogRoute, onDismiss: {
            guard let category = moreTagsCategory else { return }
            moreTagsCategory = nil
            tagFormRequest = TagFormRequest(category: category)
        }) { route in
            QuickLogCardView(onMoreTags: {
                moreTagsCategory = route.category
                quickLogRoute = nil
            })
        }
        // Fertile window, weekly check-in and Daily insights follow the data: rescheduled on launch, when
        // events or the manual fertile days change, and when the mode changes. A logged tag also writes the
        // next Daily insights note (debounced here, then off the main actor). Period reminders are rescheduled
        // by the archive action and Settings, as before.
        .task { rescheduleReminders() }
        .onReceive(myEvents.$events.dropFirst().debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in
            rescheduleReminders()
            if appSettings.dailyInsightsOn { DailyInsightsCoordinator.shared.update(write: true) }
        }
        .onReceive(fertileStore.$overrides.dropFirst()) { _ in rescheduleReminders() }
        .onChange(of: appSettings.trackingMode) { _, _ in
            refreshAuraPhase()
            rescheduleReminders()
            if appSettings.dailyInsightsOn { DailyInsightsCoordinator.shared.update(write: true) }
            AppGroup.reloadWidgets()   // the Quick Log chips follow the mode; a stale chip would write nothing
        }
    }

    private func consumePendingTap() {
        guard let route = NotificationTapRouter.shared.takePendingRoute() else { return }
        if route.name == .rhythmxOpenPatterns {
            openPatterns()
        } else if route.name == .rhythmxOpenQuickLog {
            openQuickLog()
        } else {
            openTagForm(categoryRaw: route.userInfo["category"])
        }
    }

    private func openTagForm(categoryRaw: String?) {
        selection = 2
        tagsSegment = .tags
        tagFormRequest = TagFormRequest(category: categoryRaw.flatMap(TagCategory.init(rawValue:)) ?? appSettings.trackingMode.mainCategory)
    }

    private func openQuickLog() {
        tagFormRequest = nil
        quickLogRoute = QuickLogRoute(mode: appSettings.trackingMode)
    }

    private func openPatterns() {
        selection = 2
        tagsSegment = .patterns
    }

    private func rescheduleReminders() {
        NotificationScheduler.rescheduleAll(events: myEvents.events, overrides: fertileStore.overrides, settings: appSettings)
    }
}

#Preview {
    StartTabView()
        .environmentObject(EventStore(preview: true))
        .environmentObject(ArchivedDataStore())
        .environmentObject(AppSettings())
        .environmentObject(FertileStore())
        .environmentObject(PurchaseStore(listensForUpdates: false))
        .environmentObject(HealthSync())
}
