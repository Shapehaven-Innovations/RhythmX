//
//  SettingsCycleInfoView.swift
//  The Cycles tab: the current cycle, Log period (the same sheet as the moon on Today), the Past cycles
//  inline with a link to the full list, and the phases guide. Menopause has no periods to log, so it keeps
//  its own "Start a fresh stretch" card instead.
//

import SwiftUI

struct SettingsCycleInfoView: View {
    @EnvironmentObject var eventStore: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings

    @State private var showLogPeriod = false

    // Menopause only: the fresh stretch card and its prompts.
    @State private var selectedStartDate: Date = Date()
    @State private var selectedCycleLength: Int = 28
    @State private var showCycleGeneratedAlert = false
    @State private var showArchivedAlert = false
    @State private var showArchivePrompt = false

    /// How many Past cycles are shown here before "See all".
    static let inlinePastCycles = 5

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    currentCycleCard

                    if isMenopause { freshStretchCard } else { logPeriodCard }

                    pastCyclesSection

                    NavigationLink { PhasesFactsView() } label: {
                        row("Learn about phases", trailing: nil, moon: .full)
                    }
                    .cardStyle()
                }
                .padding(DS.Spacing.md)
            }
            .themedPage()
            .navigationTitle("Cycles")
            .sheet(isPresented: $showLogPeriod) { LogPeriodSheet() }
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
            .alert("Archive your older entries?", isPresented: $showArchivePrompt) {
                Button("Yes") {
                    archiveCurrentData()
                    generateEventsAndAlert()
                }
                Button("No", role: .cancel) {
                    generateEventsAndAlert()
                }
            } message: {
                Text("Would you like to archive entries older than \(ArchivedDataStore.menopauseArchiveAgeDays) days before starting a fresh stretch? The last week stays.")
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

    /// The Past cycles of this mode's kind: cycle blocks (Cycle, Planning and legacy) or Menopause blocks.
    private var pastCycles: [ArchivedDataBlock] {
        isMenopause ? archivedDataStore.blocks(matching: .menopause) : archivedDataStore.cycleBlocks
    }

    // MARK: - Current cycle

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

    // MARK: - Log period

    private var logPeriodCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(stats.currentCycleDay == nil
                 ? "Log your period's first day to start your cycle, even if it was a few days ago."
                 : "Log your period's first day when it comes, even if it was a few days ago. The cycle so far moves to Past cycles.")
                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Log period") { showLogPeriod = true }
        }
        .cardStyle()
    }

    /// Menopause: start over from a first day and a length; the Menopause entries stay.
    private var freshStretchCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("Start a fresh stretch").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                InfoButton(topic: InfoCopy.freshStretch)
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
    }

    // MARK: - Past cycles

    private var pastCyclesSection: some View {
        let blocks = pastCycles
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("Past cycles").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink { ArchivedDataView() } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Text("See all").font(DS.Font.label).foregroundColor(DS.Color.accent)
                        Image(systemName: "chevron.right").font(DS.Font.caption).foregroundColor(DS.Color.tertiaryText)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("See all past cycles")
                .accessibilityValue("\(archivedDataStore.archivedBlocks.count)")
            }
            .padding(.horizontal, DS.Spacing.xs)

            if blocks.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("No past cycles yet").font(DS.Font.label).foregroundColor(DS.Color.primaryText)
                    Text(isMenopause
                         ? "Entries older than a week move here when you start a fresh stretch."
                         : "When you log your next period, the cycle so far appears here.")
                        .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .cardStyle()
            } else {
                ForEach(blocks.prefix(Self.inlinePastCycles)) { block in
                    PastCycleCard(block: block)
                }
                if blocks.count > Self.inlinePastCycles {
                    NavigationLink { ArchivedDataView() } label: {
                        row("See all \(blocks.count) cycles", trailing: nil, moon: .waning)
                    }
                    .cardStyle()
                }
            }
        }
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

    // MARK: - Fresh stretch (Menopause)

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
