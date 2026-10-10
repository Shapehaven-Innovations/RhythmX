//  StartTabView.swift

import SwiftUI

struct StartTabView: View {
    @AppStorage("selectedTab") private var selection = 0
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings

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

            EventsListView()
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
    }
}

#Preview {
    StartTabView()
        .environmentObject(EventStore(preview: true))
        .environmentObject(ArchivedDataStore())
        .environmentObject(AppSettings())
}
