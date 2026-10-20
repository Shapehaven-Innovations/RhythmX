//  EventsCalendarView.swift

import SwiftUI

struct EventsCalendarView: View {
    @EnvironmentObject var eventStore: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var purchaseStore: PurchaseStore
    @EnvironmentObject var calendarSync: CalendarSync
    @State private var dateSelected: Date?
    @State private var showNotificationPrompt = false
    @State private var showExport = false

    private var daysUntilPrediction: Int? {
        CyclePredictionService.daysUntilPrediction(from: archivedDataStore.cycleBlocks)
    }

    private var stats: InsightsViewModel.CycleStats {
        InsightsViewModel(
            events: eventStore.cycleEvents,
            archivedBlocks: archivedDataStore.cycleBlocks,
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
            HStack(spacing: DS.Spacing.xs) {
                Capsule()
                    .fill(appSettings.phaseColor(for: .ovulation))
                    .frame(width: 12, height: 3)
                Text("Fertile window")
                    .font(DS.Font.micro)
                    .foregroundColor(DS.Color.secondaryText)
            }
        }
    }

    private var syncedChip: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "calendar.badge.checkmark")
                .font(DS.Font.caption.weight(.medium))
                .foregroundColor(DS.Color.accent)
                .accessibilityHidden(true)
            Text("Synced to Apple Calendar")
                .font(DS.Font.caption.weight(.medium))
                .foregroundColor(DS.Color.primaryText)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.md)
        .background(DS.Color.cardBackground)
        .cornerRadius(DS.Radius.chip)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip)
                .stroke(DS.Color.accent.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Your cycle appears in the RhythmX calendar. Change this in Settings.")
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
                    // The only other 2.0 change on this tab: a chip while Apple Calendar sync (Plus) is on and
                    // working. Without calendar access the chip is hidden and the Settings card explains why.
                    if appSettings.calendarSyncOn && purchaseStore.isPlus && calendarSync.hasAccess && !calendarSync.accessDenied {
                        syncedChip
                    }
                }
                .padding(DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xl)
            }
            .themedPage()
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showExport = true } label: {
                        Image(systemName: "printer").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Print calendar")
                    .accessibilityHint("Opens the printable calendar preview")
                }
            }
            .sheet(isPresented: $showExport) {
                ExportView(kind: .calendar)
            }
            .alert("Cycle Reminders", isPresented: $showNotificationPrompt) {
                Button("Enable") {
                    NotificationScheduler.requestPermissionIfNeeded { granted in
                        if granted {
                            UserDefaults.standard.set(true, forKey: "notificationsEnabled")
                            if let predicted = CyclePredictionService.predictedStartDate(from: archivedDataStore.cycleBlocks) {
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
        .environmentObject(FertileStore())
        .environmentObject(PurchaseStore(listensForUpdates: false))
        .environmentObject(CalendarSync())
}
