//  DailyInsightDetailView.swift
//  The daily insight pull-up a tile opens: a sheet that springs up over the phase aura, the day's moon
//  breathing in the header, the insight text revealed line by line (an Apple Intelligence tile streams its text
//  as it is written, checked as it comes, with the template text as the fallback), the "Where you are" chart
//  drawing itself, suggested tags that log in one tap, Share with the matching card, and the footers.
//  Reduce Motion shows everything at once.

import SwiftUI

/// Everything the pull-up shows, built by Today from the same stores the tile was written from.
struct DailyInsightDetailModel: Identifiable {
    let tile: DailyInsightTile
    let content: InsightDetailContent
    let facts: InsightFacts
    let mode: TrackingMode
    let phase: Event.EventType?
    let today: Date
    let shareCard: ShareCard?

    var id: String { tile.id }

    /// The template's text for this tile: shown when streaming is not possible or fails.
    var templateText: String {
        TemplateInsightWriter.tiles(for: facts).first { $0.kind == tile.kind }?.body ?? tile.body
    }
}

struct DailyInsightDetailView: View {
    let model: DailyInsightDetailModel
    let streamer: InsightTileStreaming
    /// Screenshots: render the animation at this point (0 rest, 1 complete) and do not stream.
    let fixedProgress: Double?
    /// Opens Add Tag (the main button when there is nothing to suggest).
    let onAddTag: () -> Void

    @EnvironmentObject var myEvents: EventStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var start = Date()
    @State private var text: String = ""
    @State private var isAI = false
    @State private var streaming = false
    @State private var streamEnd: Double?
    @State private var finished = false
    @State private var logged: Set<TagPick> = []
    @State private var loggedTick = 0
    @State private var shareImage: ShareCardImage?

    init(model: DailyInsightDetailModel, streamer: InsightTileStreaming = SystemInsightTileStreamer(),
         fixedProgress: Double? = nil, onAddTag: @escaping () -> Void = {}) {
        self.model = model
        self.streamer = streamer
        self.fixedProgress = fixedProgress
        self.onAddTag = onAddTag
        _text = State(initialValue: model.tile.body)
        _isAI = State(initialValue: model.tile.isAI)
    }

    private var content: InsightDetailContent { model.content }

    private var reveal: InsightReveal {
        let lines = InsightReveal.estimatedLines(text.isEmpty ? model.tile.body : text, charactersPerLine: 32)
        if streaming { return InsightReveal(lineCount: lines, textEnd: .infinity) }
        return InsightReveal(lineCount: lines, textEnd: streamEnd)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: finished || fixedProgress != nil)) { timeline in
            let elapsed = elapsed(at: timeline.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if isAI {
                        Label(streaming ? "Writing on this device" : "Written on this device", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DS.Color.accent)
                            .symbolEffect(.breathe, isActive: streaming && !reduceMotion)
                    }
                    InsightRevealText(text: text, elapsed: elapsed, reveal: reveal, streaming: streaming,
                                      sweep: (timeline.date.timeIntervalSinceReferenceDate / 1.4).truncatingRemainder(dividingBy: 1))
                    if content.chart != .none {
                        chartCard(elapsed: elapsed)
                    }
                    chips(progress: reveal.chipsProgress(at: elapsed))
                    actions
                    footers
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.lg)
            }
            .scrollIndicators(.hidden)
        }
        .background(InsightSheetBackground(phase: model.phase))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .presentationBackground { InsightSheetBackground(phase: model.phase) }
        .sensoryFeedback(.success, trigger: loggedTick)
        .sensoryFeedback(.impact(weight: .light), trigger: finished)
        .onAppear {
            start = Date()
            renderShareImage()
        }
        .task { await runStream() }
        .task(id: streaming) { await finishLater() }
    }

    // MARK: - Timeline

    private func elapsed(at date: Date) -> Double {
        if let fixedProgress { return reveal.elapsed(forProgress: fixedProgress) }
        if reduceMotion { return streaming ? 0 : reveal.total }
        return date.timeIntervalSince(start)
    }

    /// Stops the timeline once everything has played (not while text streams).
    private func finishLater() async {
        guard fixedProgress == nil, !streaming else { return }
        finished = false
        let remaining = reveal.total - Date().timeIntervalSince(start)
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining + 0.1)) }
        guard !Task.isCancelled, !streaming else { return }
        finished = true
    }

    /// An Apple Intelligence tile writes its text again as the sheet opens, streaming; anything that fails a
    /// check shows the template text, revealed from the start.
    private func runStream() async {
        guard fixedProgress == nil, model.tile.isAI, streamer.isAvailable,
              InsightTileStreamRunner.streams(kind: model.tile.kind, facts: model.facts) else { return }
        streaming = true
        text = ""
        let result = await InsightTileStreamRunner.run(streamer: streamer, kind: model.tile.kind, facts: model.facts,
                                                       fallback: model.templateText) { partial in
            text = partial
        }
        text = result.text
        isAI = result.isAI
        if result.isAI {
            streamEnd = Date().timeIntervalSince(start)
        } else {
            streamEnd = nil
            start = Date().addingTimeInterval(-InsightReveal.settle * 0.5)
        }
        streaming = false
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            BreathingMoonBadge(phase: model.mode == .menopause ? nil : model.phase,
                               size: dynamicTypeSize.isAccessibilitySize ? 44 : 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundColor(DS.Color.secondaryText)
                Text(content.title)
                    .font(.title2.bold())
                    .foregroundColor(DS.Color.primaryText)
                    .accessibilityAddTraits(.isHeader)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(DS.Color.primaryText)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Chart

    private func chartCard(elapsed: Double) -> some View {
        let isTrend: Bool = { if case .menopauseTrend = content.chart { return true }; return false }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(isTrend ? InsightDetailContent.trendTitle : InsightDetailContent.curveTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Color.primaryText)
                Spacer()
                if !isTrend {
                    Text("Typical pattern")
                        .font(.caption)
                        .foregroundColor(DS.Color.secondaryText)
                }
            }
            InsightCurveChart(chart: content.chart, progress: reveal.curveProgress(at: elapsed),
                              glow: reveal.glow(at: elapsed))
            if !isTrend {
                Text(InsightDetailContent.curveCaption + ". Not measured from your body.")
                    .font(.caption)
                    .foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(CardSurface(cornerRadius: 22))
    }

    // MARK: - Chips

    private func chips(progress: Double) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(content.chips) { pick in
                let done = logged.contains(pick)
                Button { log(pick) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: done ? "checkmark" : TagGlyph.symbol(for: pick))
                            .foregroundColor(done ? DS.Color.accent : (model.phase?.defaultPhaseColor ?? DS.Color.accent))
                        Text(pick.value).foregroundColor(DS.Color.primaryText)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(Capsule().fill(DS.Color.cardBackground))
                    .overlay(Capsule().strokeBorder(DS.Color.separator.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(done)
                .accessibilityLabel(done ? "\(pick.value), logged" : "Log \(pick.value)")
            }
        }
        .opacity(progress)
        .offset(y: (1 - progress) * 8)
    }

    // MARK: - Actions

    private var actions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            if let shareImage {
                ShareLink(item: shareImage, preview: SharePreview(shareImage.title, image: Image(uiImage: shareImage.uiImage ?? UIImage()))) {
                    Text("Share")
                        .font(.headline)
                        .foregroundColor(DS.Color.accent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(DS.Color.accent.opacity(0.14)))
                }
                .accessibilityHint("Shares the \(shareImage.title) card as an image")
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 130)
            }
            Button {
                if let pick = content.primaryChip { log(pick) } else { onAddTag() }
            } label: {
                Text(content.primaryChip.map { logged.contains($0) ? "Logged" : content.primaryTitle } ?? content.primaryTitle)
                    .font(.headline)
                    .foregroundColor(DS.Color.onAccent)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(DS.Color.accent))
            }
            .buttonStyle(.plain)
            .disabled(content.primaryChip.map { logged.contains($0) } ?? false)
        }
    }

    // MARK: - Footers

    private var footers: some View {
        VStack(spacing: 6) {
            if isAI && !streaming {
                Text("Written on this device with Apple Intelligence from your own tags. Nothing was sent anywhere.")
                    .font(.footnote)
                    .foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(InsightDetailContent.footer)
            if content.showsFertilityLine {
                Text(InsightDetailContent.fertilityFooter)
            }
        }
        .font(.caption)
        .foregroundColor(DS.Color.secondaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Doing

    /// Logs through `EventStore.logTag`, as the quick log card does; a tag already logged counts as done.
    private func log(_ pick: TagPick) {
        guard fixedProgress == nil else { return }
        _ = myEvents.logTag(pick.raw, on: model.today, mode: model.mode,
                            intensity: TagFormLogic.supportsIntensity(pick) ? .medium : nil)
        logged.insert(pick)
        loggedTick += 1
    }

    private func renderShareImage() {
        guard shareImage == nil, let card = model.shareCard else { return }
        let palette = colorScheme == .dark ? DS.Theme.current.dark : DS.Theme.current.light
        shareImage = ShareCardView.pngData(for: card, palette: palette, isDark: colorScheme == .dark).map {
            ShareCardImage(id: card.id, fileName: card.fileName, title: card.pickerTitle,
                           accessibilityDescription: card.accessibilityDescription, png: $0)
        }
    }
}

/// "See all": every daily insight for today, one card each.
struct DailyInsightsListView: View {
    let insights: DailyInsights
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    ForEach(insights.tiles) { tile in
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(tile.title).font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                            Text(tile.body).font(DS.Font.body).foregroundColor(DS.Color.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            if tile.isAI {
                                Label("Written on this device", systemImage: "sparkles")
                                    .font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                            }
                        }
                        .cardStyle()
                        .accessibilityElement(children: .combine)
                    }
                    Text("Tracking tool, not medical advice.")
                        .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(DS.Spacing.md)
            }
            .themedPage()
            .navigationTitle("My daily insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
