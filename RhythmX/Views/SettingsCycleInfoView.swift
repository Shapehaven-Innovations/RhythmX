//
//  SettingsCycleInfoView.swift
//

import SwiftUI

struct SettingsCycleInfoView: View {
    @EnvironmentObject var eventStore: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings

    @State private var selectedStartDate: Date = Date()
    @State private var selectedCycleLength: Int = 28

    @State private var showCycleGeneratedAlert = false
    @State private var showArchivedAlert = false
    @State private var showArchivePrompt = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    currentCycleCard

                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        HStack {
                            Text(isMenopause ? "Start a fresh stretch" : "Start a new cycle").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            InfoButton(topic: isMenopause ? InfoCopy.freshStretch : InfoCopy.newCycle)
                        }
                        DatePicker("First day", selection: $selectedStartDate, displayedComponents: .date)
                        Stepper(value: $selectedCycleLength, in: 20...40) {
                            Text("Length: \(selectedCycleLength) days")
                        }
                        PrimaryButton(title: "Generate cycle") {
                            if eventStore.events.isEmpty { generateEventsAndAlert() } else { showArchivePrompt = true }
                        }
                    }
                    .cardStyle()

                    VStack(spacing: 0) {
                        NavigationLink { ArchivedDataView() } label: {
                            row("Past cycles", trailing: "\(archivedDataStore.archivedBlocks.count)", moon: .waning)
                        }
                        Divider()
                        NavigationLink { PhasesFactsView() } label: {
                            row("Learn about phases", trailing: nil, moon: .full)
                        }
                    }
                    .cardStyle()
                }
                .padding(DS.Spacing.md)
            }
            .themedPage()
            .navigationTitle("Cycles")
            .alert("Cycle Events Generated", isPresented: $showCycleGeneratedAlert) {
                Button("OK") {
                    eventStore.reloadCalendarIcons()
                }
            }
            .alert("Data Archived Successfully", isPresented: $showArchivedAlert) {
                Button("OK") {
                    eventStore.reloadCalendarIcons()
                }
            }
            .alert(isMenopause ? "Archive your older entries?" : "Archive your current data?", isPresented: $showArchivePrompt) {
                Button("Yes") {
                    archiveCurrentData()
                    generateEventsAndAlert()
                }
                Button("No", role: .cancel) {
                    generateEventsAndAlert()
                }
            } message: {
                Text(isMenopause
                     ? "Would you like to archive entries older than \(ArchivedDataStore.menopauseArchiveAgeDays) days before starting a fresh stretch? The last week stays."
                     : "Would you like to archive your existing events before generating a new cycle?")
            }
        }
    }

    private var mode: TrackingMode { appSettings.trackingMode }
    private var isMenopause: Bool { mode == .menopause }

    private var stats: InsightsViewModel.CycleStats {
        InsightsViewModel(events: eventStore.cycleEvents, archivedBlocks: archivedDataStore.cycleBlocks, appSettings: appSettings).cycleStats()
    }

    /// Menopause mode: whole months since the last period, in place of the next period date.
    private var monthsSinceLastPeriod: Int? {
        let insights = MenopauseInsights.make(events: eventStore.events, today: Date())
        return insights.lastPeriod == nil ? nil : insights.monthsSinceLastPeriod
    }

    private var currentCycleCard: some View {
        HStack(spacing: DS.Spacing.md) {
            PhaseRingView(cycleLength: stats.averageCycleLength ?? 28, currentPhase: stats.currentPhase)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.currentCycleDay.map { "Day \($0) of \(stats.averageCycleLength ?? 28)" } ?? "No active cycle")
                    .font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                if isMenopause {
                    if let months = monthsSinceLastPeriod {
                        Text(months == 1 ? "1 month since last period" : "\(months) months since last period")
                            .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    }
                } else if let next = stats.nextPeriodEstimate {
                    Text(next.startOfDay < Date().startOfDay ? "Next period overdue" : "Next period \(next.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                }
            }
            Spacer()
        }
        .cardStyle()
    }

    private func row(_ title: String, trailing: String?, moon: MoonPhase) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            MoonPhaseView(phase: moon, color: DS.Color.accent, size: 16)
            Text(title).font(DS.Font.label).foregroundColor(DS.Color.primaryText)
            Spacer()
            if let trailing { Text(trailing).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText) }
            Image(systemName: "chevron.right").font(DS.Font.caption).foregroundColor(DS.Color.tertiaryText)
        }
        .padding(.vertical, DS.Spacing.sm)
    }
    /// Archives under the current mode. The grouping lives in `ArchivedDataStore.archiveCurrent`.
    private func archiveCurrentData() {
        guard archivedDataStore.archiveCurrent(from: eventStore, mode: mode) != nil else { return }
        showArchivedAlert = true
    }

    private func generateEventsAndAlert() {
        eventStore.generateCycleEvents(
            startDate: selectedStartDate,
            cycleLength: selectedCycleLength
        )
        showCycleGeneratedAlert = true
    }
}

