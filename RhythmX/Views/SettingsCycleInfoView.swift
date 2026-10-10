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
                        Text("Start a new cycle").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                        DatePicker("First day", selection: $selectedStartDate, displayedComponents: .date)
                        Stepper(value: $selectedCycleLength, in: 20...40) {
                            Text("Length: \(selectedCycleLength) days")
                        }
                        PrimaryButton(title: "Generate cycle") {
                            if eventStore.events.isEmpty { generateEventsAndAlert() } else { showArchivePrompt = true }
                        }
                        Text("If you already have events, you'll be asked whether to archive them first.")
                            .font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
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
            .background(DS.Color.pageBackground.ignoresSafeArea())
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
            .alert("Archive your current data?", isPresented: $showArchivePrompt) {
                Button("Yes") {
                    archiveCurrentData()
                    generateEventsAndAlert()
                }
                Button("No", role: .cancel) {
                    generateEventsAndAlert()
                }
            } message: {
                Text("Would you like to archive your existing events before generating a new cycle?")
            }
        }
    }

    private var stats: InsightsViewModel.CycleStats {
        InsightsViewModel(events: eventStore.events, archivedBlocks: archivedDataStore.archivedBlocks, appSettings: appSettings).cycleStats()
    }

    private var currentCycleCard: some View {
        HStack(spacing: DS.Spacing.md) {
            PhaseRingView(cycleLength: stats.averageCycleLength ?? 28, currentPhase: stats.currentPhase)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.currentCycleDay.map { "Day \($0) of \(stats.averageCycleLength ?? 28)" } ?? "No active cycle")
                    .font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                if let next = stats.nextPeriodEstimate {
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
    private func archiveCurrentData() {
        guard !eventStore.events.isEmpty else { return }

        let groupedPhases = Dictionary(grouping: eventStore.events) { $0.eventType }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { (key, events) in
                ArchivedDataBlock.PhaseEvents(eventType: key, events: events)
            }

        let newBlock = ArchivedDataBlock(
            id: UUID(),
            date: Date(),
            groupedEvents: groupedPhases
        )

        archivedDataStore.appendArchivedBlock(newBlock)
        eventStore.clearAllEvents()
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

