//  QuickLogCardView.swift
//  Where a Daily insights tap lands: a compact glass card that asks one question, offers four round choices
//  from her own frequent and phase tags plus "None of these", logs them in one tap (medium where a strength
//  applies) and hands over to the full Add Tags sheet with "More tags". The logic is in QuickLogCardLogic.

import SwiftUI

struct QuickLogCardView: View {
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Screenshots pass a fixed clock; the app uses the real one.
    var now: Date? = nil
    /// Opens the full Add Tags sheet (the presenter closes this card first).
    var onMoreTags: () -> Void = {}

    @State private var selection = QuickLogSelection()
    @State private var choices: [TagPick] = []
    @State private var logged: [TagPick]?
    @State private var height: CGFloat = 360
    @State private var loggedTick = 0

    init(now: Date? = nil, initialSelection: QuickLogSelection = QuickLogSelection(), onMoreTags: @escaping () -> Void = {}) {
        self.now = now
        self.onMoreTags = onMoreTags
        _selection = State(initialValue: initialSelection)
    }

    private var today: Date { now ?? Date() }
    private var mode: TrackingMode { appSettings.trackingMode }
    private var phase: Event.EventType? {
        guard mode != .menopause else { return nil }
        return myEvents.cycleEvents.first { $0.date.startOfDay == today.startOfDay }?.eventType
    }
    private var canLog: Bool { TagFormLogic.canHoldTags(on: today, mode: mode, events: myEvents.events) }
    private var tint: Color { phase?.defaultPhaseColor ?? DS.Color.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let logged {
                settled(logged)
            } else {
                question
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(34)
        // Glass with enough of the card colour that Today behind it never reads through the text.
        .presentationBackground {
            ZStack {
                Rectangle().fill(.regularMaterial)
                DS.Color.cardBackground.opacity(0.82)
            }
        }
        .sensoryFeedback(.success, trigger: loggedTick)
        .onAppear {
            if choices.isEmpty {
                choices = QuickLogCardLogic.choices(
                    mode: mode, phase: phase, events: myEvents.events,
                    history: TagFormLogic.historyTags(phase: phase, blocks: archivedDataStore.cycleBlocks),
                    today: today)
            }
        }
    }

    // MARK: - Question

    private var question: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(QuickLogCardLogic.eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.6)
                        .foregroundColor(DS.Color.secondaryText)
                    Text(QuickLogCardLogic.question(mode: mode, phase: phase))
                        .font(.title3.weight(.semibold))
                        .foregroundColor(DS.Color.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.subheadline.weight(.semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Close")
            }

            if !canLog {
                Text("Today is outside your cycle, so tags cannot be saved here.")
                    .font(.footnote)
                    .foregroundColor(DS.Color.secondaryText)
                    .padding(.top, 8)
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top),
                                count: dynamicTypeSize.isAccessibilitySize ? 2 : 5)
            LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                RoundGlyphButton(label: "None of these", symbol: "nosign", isSelected: selection.noneChosen,
                                 diameter: 56, restFill: tint.opacity(0.16), restInk: tint) {
                    animate { selection.chooseNone() }
                }
                ForEach(choices) { pick in
                    RoundGlyphButton(label: pick.value, symbol: TagGlyph.symbol(for: pick), isSelected: selection.contains(pick),
                                     diameter: 56, restFill: tint.opacity(0.16), restInk: tint) {
                        animate { selection.toggle(pick) }
                    }
                }
            }
            .padding(.top, 16)
            .sensoryFeedback(.selection, trigger: selection)

            HStack(spacing: 10) {
                Button {
                    onMoreTags()
                } label: {
                    Text("More tags")
                        .font(.headline)
                        .foregroundColor(DS.Color.accent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(DS.Color.primaryText.opacity(0.07)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Add Tags with every category")

                Button(action: apply) {
                    Text(selection.buttonTitle)
                        .font(.headline)
                        .foregroundColor(DS.Color.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(DS.Color.accent.opacity(applyEnabled ? 1 : 0.4)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!applyEnabled)
                .accessibilityHint(selection.noneChosen ? "Closes the card" : "Logs the picked tags for today")
            }
            .padding(.top, 18)
        }
    }

    private var applyEnabled: Bool { selection.noneChosen || (selection.canApply && canLog) }

    // MARK: - Settled

    private func settled(_ picks: [TagPick]) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.title3.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 52, height: 52)
                .background(Circle().fill(tint.opacity(0.22)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(QuickLogCardLogic.loggedTitle(cycleDay: mode == .menopause ? nil
                                                    : TagFormLogic.cycleDay(on: today, events: myEvents.events)))
                    .font(.headline).foregroundColor(DS.Color.primaryText)
                Text(QuickLogCardLogic.loggedDetail(picks))
                    .font(.subheadline).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func animate(_ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { change() } }
    }

    private func apply() {
        guard !selection.noneChosen else { dismiss(); return }
        let written = QuickLogCardLogic.log(selection, store: myEvents, on: today, mode: mode)
        guard !written.isEmpty else { dismiss(); return }
        loggedTick += 1
        animate { logged = written }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            dismiss()
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickLogCardView()
            .environmentObject(EventStore(preview: true))
            .environmentObject(ArchivedDataStore())
            .environmentObject(AppSettings())
    }
}
