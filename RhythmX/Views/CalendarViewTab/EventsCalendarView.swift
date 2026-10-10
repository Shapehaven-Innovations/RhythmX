//  EventsCalendarView.swift

import SwiftUI

struct EventsCalendarView: View {
    @EnvironmentObject var eventStore: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @State private var dateSelected: Date?
    @State private var showNotificationPrompt = false

    private var daysUntilPrediction: Int? {
        CyclePredictionService.daysUntilPrediction(from: archivedDataStore.archivedBlocks)
    }

    private var stats: InsightsViewModel.CycleStats {
        InsightsViewModel(
            events: eventStore.events,
            archivedBlocks: archivedDataStore.archivedBlocks,
            appSettings: appSettings
        ).cycleStats()
    }

    private var legend: some View {
        FlowLayout(spacing: DS.Spacing.md) {
            ForEach(Event.EventType.allCases) { phase in
                HStack(spacing: DS.Spacing.xs) {
                    MoonPhaseView(phase: phase.moonPhase, color: appSettings.phaseColor(for: phase), size: 12)
                    Text(phase.rawValue.capitalized)
                        .font(DS.Font.micro)
                        .foregroundColor(DS.Color.secondaryText)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    if let days = daysUntilPrediction, days >= 0, days <= 3 {
                        PredictionBannerView(daysUntil: days)
                    }
                    TodayCard(stats: stats)
                    PhaseCalendarView(selectedDate: $dateSelected, predictedStart: stats.nextPeriodEstimate)
                    legend
                    if let selected = dateSelected {
                        DayPanelView(date: selected)
                    }
                }
                .padding(DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xl)
            }
            .background(DS.Color.pageBackground.ignoresSafeArea())
            .navigationTitle("Calendar")
            .alert("Cycle Reminders", isPresented: $showNotificationPrompt) {
                Button("Enable") {
                    NotificationScheduler.requestPermissionIfNeeded { granted in
                        if granted {
                            UserDefaults.standard.set(true, forKey: "notificationsEnabled")
                            if let predicted = CyclePredictionService.predictedStartDate(from: archivedDataStore.archivedBlocks) {
                                NotificationScheduler.scheduleCycleReminders(
                                    for: predicted, dayBefore: true, dayOf: true
                                )
                            }
                        }
                    }
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Want reminders when your next cycle is near?")
            }
            .onReceive(NotificationCenter.default.publisher(for: .rhythmxPromptNotifications)) { _ in
                showNotificationPrompt = true
            }
        }
    }
}

#Preview {
    EventsCalendarView()
        .environmentObject(EventStore(preview: true))
        .environmentObject(ArchivedDataStore())
        .environmentObject(AppSettings())
}
