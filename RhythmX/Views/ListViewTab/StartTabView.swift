//  StartTabView.swift

import SwiftUI
import Combine

struct StartTabView: View {
    @AppStorage("selectedTab") private var selection = 0
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var fertileStore: FertileStore

    /// A notification tap asked for the tag form on this category.
    @State private var tagFormRequest: TagFormRequest?
    /// Tags | Patterns on the Tags tab; the weekly check-in tap selects Patterns.
    @State private var tagsSegment: TagsSegment = .tags

    private struct TagFormRequest: Identifiable {
        let category: TagCategory
        var id: String { category.rawValue }
    }

    private var persistenceErrorMessage: String? {
        myEvents.persistenceError ?? archivedDataStore.persistenceError
    }

    var body: some View {
        TabView(selection: $selection) {
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
                .tag(0)

            EventsCalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(1)

            EventsListView(segment: $tagsSegment)
                .tabItem { Label("Tags", systemImage: "tag.fill") }
                .tag(2)

            SettingsCycleInfoView()
                .tabItem { Label("Cycles", systemImage: "moon.circle") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(DS.Color.accent)
        // The theme tints the tab bar (card colour with a little accent); the id is read again on redraw.
        .toolbarBackground(DS.Color.tabBar, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
        // Notification taps (NotificationTapRouter): the tag form on a category, or Patterns on the Tags tab.
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
        .sheet(item: $tagFormRequest) { request in
            TagFormView(initialCategory: request.category)
        }
        // Fertile window, check-in and tag reminders follow the data: rescheduled on launch, when events
        // or the manual fertile days change, and when the mode changes. Period reminders are rescheduled
        // by the archive action and Settings, as before.
        .task { rescheduleReminders() }
        .onReceive(myEvents.$events.dropFirst().debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in
            rescheduleReminders()
        }
        .onReceive(fertileStore.$overrides.dropFirst()) { _ in rescheduleReminders() }
        .onChange(of: appSettings.trackingMode) { _, _ in
            rescheduleReminders()
            AppGroup.reloadWidgets()   // the Quick Log chips follow the mode; a stale chip would write nothing
        }
    }

    private func consumePendingTap() {
        guard let route = NotificationTapRouter.shared.takePendingRoute() else { return }
        if route.name == .rhythmxOpenPatterns {
            openPatterns()
        } else {
            openTagForm(categoryRaw: route.userInfo["category"])
        }
    }

    private func openTagForm(categoryRaw: String?) {
        selection = 2
        tagsSegment = .tags
        tagFormRequest = TagFormRequest(category: categoryRaw.flatMap(TagCategory.init(rawValue:)) ?? appSettings.trackingMode.mainCategory)
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
}
