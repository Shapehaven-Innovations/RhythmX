//  LogPeriodSheet.swift
//  The one Log Period sheet, opened from the moon on Today and from Cycles: the period's first day (today by
//  default, up to sixty days back, never after today or inside a Past cycle), the cycle length, what the choice
//  does in plain words, and the actions the day allows (`PeriodStartPlan.offer`): start a new cycle, or early
//  in a cycle move its start instead. The stores are changed only here, through their own archive and replace
//  calls.

import SwiftUI

struct LogPeriodSheet: View {
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    /// Screenshots pass a fixed clock and a preselected day; the app uses the real clock and today.
    var now: Date? = nil
    var initialStart: Date? = nil
    /// Called once the cycle has been written (Today plays its haptic from this).
    var onLogged: () -> Void = {}

    @State private var start = Date()
    @State private var cycleLength = 28
    @State private var didSetUp = false
    @State private var height: CGFloat = 420

    private var today: Date { now ?? Date() }
    private var mode: TrackingMode { appSettings.trackingMode }
    /// Planning keeps its own Past cycles; a period logged in Menopause (never offered) would count as Cycle.
    private var archiveMode: TrackingMode { mode == .planning ? .planning : .cycle }

    private var range: ClosedRange<Date> {
        PeriodStartPlan.pickerRange(today: today, blocks: archivedDataStore.archivedBlocks)
    }

    private var offer: PeriodStartPlan.Offer {
        PeriodStartPlan.offer(events: myEvents.events, start: start, today: today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            DatePicker("First day", selection: $start, in: range, displayedComponents: .date)
                .font(DS.Font.label.weight(.medium))
                .foregroundColor(DS.Color.primaryText)
                .tint(DS.Color.accent)
                .padding(.top, DS.Spacing.md)
                .accessibilityHint("The first day of your period, today unless it started earlier")

            Stepper(value: $cycleLength, in: PeriodStartPlan.cycleLengthRange) {
                Text("Cycle length: \(cycleLength) days")
                    .font(DS.Font.label.weight(.medium))
                    .foregroundColor(DS.Color.primaryText)
            }
            .tint(DS.Color.accent)
            .padding(.top, DS.Spacing.sm)
            .accessibilityValue("\(cycleLength) days")

            Text(offer.message)
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Spacing.md)
                .animation(nil, value: start)

            VStack(spacing: DS.Spacing.sm) {
                ForEach(Array(offer.actions.enumerated()), id: \.element) { index, action in
                    if index == 0 {
                        PrimaryButton(title: action.title) { perform(action) }
                    } else {
                        SecondaryButton(title: action.title) { perform(action) }
                    }
                }
            }
            .padding(.top, DS.Spacing.md)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, DS.Spacing.md)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        // Glass with enough of the card colour that the page behind never reads through the text.
        .presentationBackground {
            ZStack {
                Rectangle().fill(.regularMaterial)
                DS.Color.cardBackground.opacity(0.82)
            }
        }
        .onAppear {
            guard !didSetUp else { return }
            didSetUp = true
            start = PeriodStartPlan.clampedStart(initialStart ?? today, today: today, blocks: archivedDataStore.archivedBlocks)
            cycleLength = PeriodStartPlan.defaultCycleLength(
                snapshot: PhaseWidgetSnapshot.make(events: myEvents.events, archived: archivedDataStore.archivedBlocks, today: today))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LOG PERIOD")
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundColor(DS.Color.secondaryText)
                Text("When did it start?")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(DS.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            InfoButton(topic: InfoCopy.newCycle, compact: false)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold)).frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Actions

    /// Writes the plan for the chosen day through the stores' own archive and replace calls, then closes.
    private func perform(_ action: PeriodStartPlan.Offer.Action) {
        let start = PeriodStartPlan.clampedStart(start, today: today, blocks: archivedDataStore.archivedBlocks)
        switch action {
        case .startNewCycle:
            // The cycle so far goes to Past cycles and a new cycle starts on the chosen day.
            let plan = PeriodStartPlan.make(events: myEvents.events, start: start, cycleLength: cycleLength)
            archivedDataStore.archiveCurrent(events: plan.archive, mode: archiveMode)
            myEvents.replaceAll(plan.events)
        case .moveStart:
            // The current start was a mistake: the cycle starts again on the chosen day and nothing new is added
            // to Past cycles (the days before it join the cycle before, or only their tags are kept).
            let plan = PeriodStartPlan.moveStart(events: myEvents.events, blocks: archivedDataStore.archivedBlocks,
                                                 start: start, cycleLength: cycleLength)
            if let blocks = plan.blocks { archivedDataStore.replaceAll(blocks) }
            if !plan.newArchive.isEmpty {
                archivedDataStore.archiveCurrent(events: plan.newArchive, mode: archiveMode)
            }
            myEvents.replaceAll(plan.events)
        }
        myEvents.reloadCalendarIcons()
        onLogged()
        dismiss()
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            LogPeriodSheet()
                .environmentObject(EventStore(preview: true))
                .environmentObject(ArchivedDataStore())
                .environmentObject(AppSettings())
        }
}
