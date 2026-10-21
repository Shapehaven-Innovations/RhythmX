//  TagPatternsView.swift
//  The Patterns segment of the Tags tab: the optional on-device summary, the tag-by-phase heatmap
//  (tag-by-week in Menopause), and the "Patterns found" card. Everything here is free.

import SwiftUI

// MARK: - View model

/// Pure state for the Patterns segment, so the summary wiring can be tested with a fake summarizer.
struct TagPatternsViewModel {
    let mode: TrackingMode
    let heatmap: [TagPhaseRow]
    let findings: [PatternFinding]
    /// Cycles the finder can see; weeks with menopause tags in Menopause.
    let cyclesAvailable: Int
    let summarizer: any PatternSummarizing

    init(events: [Event], archivedBlocks: [ArchivedDataBlock], mode: TrackingMode,
         summarizer: any PatternSummarizing, today: Date = Date()) {
        self.mode = mode
        self.summarizer = summarizer
        heatmap = PatternFinder.heatmap(events: events, archivedBlocks: archivedBlocks, mode: mode, today: today)
        findings = PatternFinder.findings(events: events, archivedBlocks: archivedBlocks, mode: mode, today: today)
        cyclesAvailable = mode == .menopause
            ? PatternFinder.weeksAvailable(events: events, archivedBlocks: archivedBlocks, today: today)
            : PatternFinder.cyclesAvailable(events: events, archivedBlocks: archivedBlocks)
    }

    /// The summary card shows only when the model is available and there are facts to give it.
    var showsSummary: Bool { summarizer.isAvailable && !findings.isEmpty }

    var cyclesNeeded: Int { PatternFinder.cyclesNeeded(available: cyclesAvailable) }

    var unit: String { mode == .menopause ? "week" : "cycle" }

    var emptyStateMessage: String {
        let n = cyclesNeeded
        let noun = n == 1 ? unit : unit + "s"
        if mode == .menopause {
            return "Log tags for \(n) more \(noun) to see patterns here."
        }
        return "Log \(n) more \(noun) to see patterns here."
    }

    var suggestedQuestions: [String] { PatternSummaryProvider.suggestedQuestions(for: mode) }

    /// Asks the summarizer with the findings only. With no findings nothing is asked, so nothing can be invented.
    func summary(question: String?) async throws -> String {
        guard !findings.isEmpty else { return "" }
        return try await summarizer.summarize(findings, question: question)
    }
}

// MARK: - View

struct TagPatternsView: View {
    static let disclaimer = "Patterns come from your own logs. Not medical advice."

    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var summarizer: any PatternSummarizing = PatternSummaryProvider()
    var today: Date = Date()

    @State private var summaryText = ""
    @State private var summaryBusy = false
    @State private var summaryFailed = false
    @State private var activeQuestion: String?

    private var viewModel: TagPatternsViewModel {
        TagPatternsViewModel(events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks,
                             mode: appSettings.trackingMode, summarizer: summarizer, today: today)
    }

    var body: some View {
        let vm = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if vm.showsSummary {
                    summaryCard(vm)
                }
                heatmapCard(vm)
                findingsCard(vm)
                Text(Self.disclaimer)
                    .font(DS.Font.micro)
                    .foregroundColor(DS.Color.secondaryText)
                    .padding(.horizontal, DS.Spacing.xs)
            }
            .padding(DS.Spacing.md)
        }
        .task(id: vm.findings.map(\.id).joined(separator: "|") + vm.mode.rawValue) {
            guard vm.showsSummary else { return }
            await writeSummary(vm, question: nil)
        }
    }

    // MARK: - Summary card

    private func summaryCard(_ vm: TagPatternsViewModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "sparkles").foregroundColor(DS.Color.accent)
                Text("Summary").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            }
            if summaryBusy {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                    Text("Writing...").font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                }
            } else if summaryFailed {
                Text("The summary could not be written right now. The patterns below still stand.")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
            } else if !summaryText.isEmpty {
                if let question = activeQuestion {
                    Text(question).font(DS.Font.caption.weight(.semibold)).foregroundColor(DS.Color.secondaryText)
                }
                Text(summaryText).font(DS.Font.label).foregroundColor(DS.Color.primaryText)
            }
            FlowLayout(spacing: DS.Spacing.xs) {
                ForEach(vm.suggestedQuestions, id: \.self) { question in
                    ChipButton(title: question) {
                        Task { await writeSummary(vm, question: question) }
                    }
                    .disabled(summaryBusy)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Label(PatternSummaryProvider.onDeviceLabel, systemImage: "lock")
                Label(PatternSummaryProvider.disclaimer, systemImage: "info.circle")
            }
            .font(DS.Font.micro)
            .foregroundColor(DS.Color.secondaryText)
        }
        .cardStyle()
    }

    @MainActor
    private func writeSummary(_ vm: TagPatternsViewModel, question: String?) async {
        summaryBusy = true
        summaryFailed = false
        activeQuestion = question
        defer { summaryBusy = false }
        do {
            summaryText = try await vm.summary(question: question)
        } catch {
            summaryText = ""
            summaryFailed = true
        }
    }

    // MARK: - Heatmap

    private func heatmapCard(_ vm: TagPatternsViewModel) -> some View {
        let isWeekly = vm.mode == .menopause
        let maxCount = vm.heatmap.flatMap(\.cells).map(\.count).max() ?? 0
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(isWeekly ? "Tags by Week" : "Tags by Phase")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text(isWeekly
                 ? "Your most logged tags over the last 8 weeks, oldest week on the left. Every tap counts. Tap a tag for detail."
                 : "Your most logged tags across your last 6 cycles. Darker means more often. Tap a tag for detail.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            if vm.heatmap.isEmpty {
                placeholderCard(icon: "square.grid.3x3",
                    message: isWeekly
                        ? "Log Menopause tags such as Hot Flashes from the Calendar or the Tags tab. The weekly grid shows here."
                        : "Log tags on your cycle days from the Calendar or the Tags tab. The phase grid shows here.")
            } else {
                VStack(spacing: DS.Spacing.xs) {
                    heatmapHeader(vm)
                    ForEach(vm.heatmap) { row in
                        NavigationLink {
                            TagDetailView(row: row, mode: vm.mode, today: today)
                        } label: {
                            heatmapRow(row, maxCount: maxCount, isWeekly: isWeekly)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var labelWidth: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? nil : 104
    }

    @ViewBuilder
    private func heatmapHeader(_ vm: TagPatternsViewModel) -> some View {
        let columns = HStack(spacing: DS.Spacing.xs) {
            if vm.mode == .menopause {
                ForEach(0..<PatternFinder.weeks, id: \.self) { index in
                    Text(weekLabel(index))
                        .font(DS.Font.micro)
                        .foregroundColor(DS.Color.secondaryText)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(weekAccessibilityLabel(index))
                }
            } else {
                ForEach(Event.EventType.allCases) { phase in
                    MoonPhaseView(phase: phase.moonPhase, color: appSettings.phaseColor(for: phase), size: 18)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(false)
                        .accessibilityLabel(phase.displayName)
                }
            }
        }
        if dynamicTypeSize.isAccessibilitySize {
            columns
        } else {
            HStack(spacing: DS.Spacing.sm) {
                Color.clear.frame(width: labelWidth, height: 1)
                columns
            }
        }
    }

    private func heatmapRow(_ row: TagPhaseRow, maxCount: Int, isWeekly: Bool) -> some View {
        let label = Text(row.label)
            .font(DS.Font.caption)
            .foregroundColor(DS.Color.primaryText)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(0.85)
        let cells = HStack(spacing: DS.Spacing.xs) {
            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                RoundedRectangle(cornerRadius: DS.Radius.chip / 2, style: .continuous)
                    .fill(cellColor(cell, maxCount: maxCount))
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .overlay {
                        if cell.count > 0 {
                            Text("\(cell.count)")
                                .font(DS.Font.micro.weight(.semibold))
                                .foregroundColor(DS.Color.primaryText)
                                .minimumScaleFactor(0.7)
                        }
                    }
            }
        }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    label
                    cells
                }
                .padding(.vertical, DS.Spacing.xs)
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    label.frame(width: labelWidth, alignment: .leading)
                    cells
                }
            }
        }
        .frame(minHeight: 44)   // each row is a tap target that opens tag detail
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(row, isWeekly: isWeekly))
        .accessibilityHint("Opens tag detail")
    }

    private func cellColor(_ cell: TagPhaseCell, maxCount: Int) -> Color {
        guard cell.count > 0, maxCount > 0 else { return Color(UIColor.tertiarySystemFill) }
        let base = cell.phase.map { appSettings.phaseColor(for: $0) } ?? DS.Color.accent
        let intensity = 0.25 + 0.75 * Double(cell.count) / Double(maxCount)
        return base.opacity(intensity)
    }

    private func weekLabel(_ index: Int) -> String {
        let weeksAgo = PatternFinder.weeks - 1 - index
        return weeksAgo == 0 ? "Now" : "\(weeksAgo)w"
    }

    private func weekAccessibilityLabel(_ index: Int) -> String {
        let weeksAgo = PatternFinder.weeks - 1 - index
        switch weeksAgo {
        case 0: return "This week"
        case 1: return "1 week ago"
        default: return "\(weeksAgo) weeks ago"
        }
    }

    private func rowAccessibilityLabel(_ row: TagPhaseRow, isWeekly: Bool) -> String {
        let parts = row.cells.enumerated().compactMap { index, cell -> String? in
            guard cell.count > 0 else { return nil }
            let column = isWeekly ? weekAccessibilityLabel(index) : (cell.phase?.displayName ?? "")
            return "\(cell.count) in \(column)"
        }
        return "\(row.label): " + (parts.isEmpty ? "none" : parts.joined(separator: ", "))
    }

    // MARK: - Patterns found

    private func findingsCard(_ vm: TagPatternsViewModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Patterns Found")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            if vm.findings.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(vm.emptyStateMessage)
                        .font(DS.Font.label)
                        .foregroundColor(DS.Color.primaryText)
                    Text("A pattern needs the same tag in at least \(PatternFinder.minimumCycles) \(vm.unit)s.")
                        .font(DS.Font.caption)
                        .foregroundColor(DS.Color.secondaryText)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(vm.mode == .menopause
                     ? "Tags that came up in at least \(PatternFinder.minimumCycles) of the last \(PatternFinder.weeks) weeks."
                     : "Tags that came up at the same point in at least \(PatternFinder.minimumCycles) of your last cycles.")
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.secondaryText)
                VStack(spacing: 0) {
                    ForEach(vm.findings) { finding in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.sentence)
                                .font(DS.Font.label)
                                .foregroundColor(DS.Color.primaryText)
                            Text(finding.evidence)
                                .font(DS.Font.caption)
                                .foregroundColor(DS.Color.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, DS.Spacing.sm)
                        .accessibilityElement(children: .combine)
                        if finding.id != vm.findings.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Placeholder

    private func placeholderCard(icon: String, message: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: icon).foregroundColor(DS.Color.secondaryText).frame(width: DS.Spacing.lg)
            Text(message).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.pageBackground)
        .cornerRadius(DS.Radius.chip)
    }
}

#Preview {
    NavigationStack {
        TagPatternsView()
            .background(DS.Color.pageBackground)
    }
    .environmentObject(EventStore(preview: true))
    .environmentObject(ArchivedDataStore())
    .environmentObject(AppSettings())
}
