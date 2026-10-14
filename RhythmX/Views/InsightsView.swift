// RhythmX/Views/InsightsView.swift
import SwiftUI
import Charts

struct InsightsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var appSettings: AppSettings

    @State private var selectedPhase: Event.EventType? = nil

    var body: some View {
        let vm = InsightsViewModel(
            events: myEvents.events,
            archivedBlocks: archivedDataStore.archivedBlocks,
            appSettings: appSettings
        )
        return NavigationStack {
            ScrollView {
                if vm.events.isEmpty && vm.archivedBlocks.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        InsightsHeroCard(stats: vm.cycleStats())
                        tagFrequencyChart(vm).cardStyle()
                        tagsOverMonthChart(vm).cardStyle()
                        tagCategoryDonut(vm).cardStyle()
                        fertilityWindowChart(vm).cardStyle()
                        cervicalMucusChart(vm).cardStyle()
                    }
                    .padding(DS.Spacing.md)
                }
            }
            .background(DS.Color.pageBackground.ignoresSafeArea())
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer(minLength: DS.Spacing.xxl)
            MoonPhaseView(phase: .full, color: DS.Color.moon, isActive: true, size: 56)
            Text("No Insights Yet")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("Start a cycle in Cycles and log a few tags to see your patterns here.")
                .font(DS.Font.label)
                .foregroundColor(DS.Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
            WaveBackground(drift: true)
                .frame(height: 160)
                .padding(.top, DS.Spacing.xl)
        }
    }

    // MARK: - Chart 1: Tag Breakdown by Phase

    @ViewBuilder
    private func tagFrequencyChart(_ vm: InsightsViewModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Tag Breakdown by Phase")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("Category mix per phase. Tap a phase number to see its top tags.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            let data = vm.stackedTagData
            if data.isEmpty {
                placeholderCard(icon: "tag",
                    message: "Log tags on your events to see which symptoms appear most in each phase.")
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Percent", item.percentage),
                        y: .value("Phase", item.phaseName)
                    )
                    .foregroundStyle(by: .value("Category", item.categoryName))
                    .cornerRadius(2)
                }
                .chartForegroundStyleScale(
                    domain: InsightsViewModel.categoryNames,
                    range: InsightsViewModel.categoryNames.map { InsightsViewModel.categoryColors[$0] ?? .gray }
                )
                .chartXScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%").font(.caption2) } }
                        AxisGridLine()
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 130)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                HStack(spacing: DS.Spacing.md) {
                    ForEach(Event.EventType.allCases, id: \.self) { phase in
                        if !vm.topTagsForPhase(phase).isEmpty {
                            Button {
                                selectedPhase = selectedPhase == phase ? nil : phase
                            } label: {
                                HStack(spacing: DS.Spacing.xs) {
                                    PhaseNumberBadge(phase: phase)
                                    Image(systemName: selectedPhase == phase ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(DS.Color.secondaryText)
                                }
                            }
                        }
                    }
                    Spacer()
                }

                if let phase = selectedPhase {
                    let top = vm.topTagsForPhase(phase)
                    if !top.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("Top tags - \(phase.displayName)")
                                .font(DS.Font.caption.weight(.semibold))
                                .foregroundColor(DS.Color.primaryText)
                            ForEach(top) { item in
                                HStack {
                                    Text(item.shortTag).font(DS.Font.caption).foregroundColor(DS.Color.primaryText)
                                    Spacer()
                                    Text("\(item.count)×").font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                                }
                            }
                        }
                        .padding(DS.Spacing.sm)
                        .background(DS.Color.cardBackground)
                        .cornerRadius(DS.Radius.chip)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.xs) {
                    ForEach(vm.categoryLegendItems, id: \.name) { item in
                        HStack(spacing: DS.Spacing.xs) {
                            RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 10, height: 10)
                            Text(item.name).font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                            Spacer()
                        }
                    }
                }
                .padding(.top, DS.Spacing.xs)
            }
        }
    }

    // MARK: - Chart 1b: Tags Over the Month

    @ViewBuilder
    private func tagsOverMonthChart(_ vm: InsightsViewModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Tags Over the Month")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("Tags logged per cycle day, colored by phase.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            let data = vm.dailyTagData
            if data.isEmpty && vm.tagsOverMonthAverageLine.isEmpty {
                placeholderCard(icon: "calendar.badge.plus",
                    message: "Log tags on event days to see your monthly pattern.")
            } else {
                Chart {
                    ForEach(data) { item in
                        BarMark(x: .value("Day", item.cycleDay), y: .value("Tags", item.count))
                            .foregroundStyle(item.color)
                            .cornerRadius(3)
                    }
                    ForEach(vm.tagsOverMonthAverageLine) { point in
                        LineMark(
                            x: .value("Day", point.cycleDay),
                            y: .value("Avg", point.average)
                        )
                        .foregroundStyle(DS.Color.secondaryText.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                    }
                }
                .frame(height: 150)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .chartXAxis {
                    AxisMarks(preset: .aligned) { value in
                        if let v = value.as(Int.self), v % 5 == 0 || v == 1 {
                            AxisValueLabel { Text("Day \(v)").font(.caption2) }
                        }
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel().font(.caption2)
                        AxisGridLine()
                    }
                }

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    FlowLayout(spacing: DS.Spacing.md) {
                        ForEach(Event.EventType.allCases, id: \.self) { phase in
                            HStack(spacing: DS.Spacing.xs) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(appSettings.phaseColor(for: phase))
                                    .frame(width: 10, height: 10)
                                Text(phase.rawValue.capitalized)
                                    .font(DS.Font.micro)
                                    .foregroundColor(DS.Color.secondaryText)
                            }
                        }
                    }
                    if !vm.tagsOverMonthAverageLine.isEmpty {
                        HStack(spacing: DS.Spacing.xs) {
                            Path { path in
                                path.move(to:    CGPoint(x: 0, y: 5))
                                path.addLine(to: CGPoint(x: 14, y: 5))
                            }
                            .stroke(DS.Color.secondaryText.opacity(0.4),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .frame(width: 14, height: 10)
                            Text("Dashed = archived average")
                                .font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                        }
                    }
                }
                .padding(.top, DS.Spacing.xs)
            }
        }
    }

    // MARK: - Chart 1c: Tag Category Mix

    @ViewBuilder
    private func tagCategoryDonut(_ vm: InsightsViewModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Tag Category Mix")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("Overall breakdown of everything you've tracked.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            let data = vm.tagCategoryTotals
            if data.isEmpty {
                placeholderCard(icon: "chart.pie", message: "Log tags to see your category breakdown here.")
            } else {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.lg))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Spacing.lg))) {
                    Chart(data) { item in
                        SectorMark(angle: .value("Count", item.count),
                                   innerRadius: .ratio(0.55), angularInset: 1.5)
                            .foregroundStyle(item.color)
                            .cornerRadius(3)
                    }
                    .frame(width: 130, height: 130)
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        ForEach(data) { item in
                            HStack(spacing: DS.Spacing.xs) {
                                RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 10, height: 10)
                                Text(item.category).font(DS.Font.caption).foregroundColor(DS.Color.primaryText)
                                Spacer()
                                Text("\(item.count)").font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Chart 3: Phase Timeline

    @ViewBuilder
    private func fertilityWindowChart(_ vm: InsightsViewModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Phase Timeline")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("When each phase occurs across your cycle days.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            let spans = vm.phaseSpans
            if spans.isEmpty && vm.phaseSpansArchiveAverage.isEmpty {
                placeholderCard(icon: "calendar.badge.clock",
                    message: "Generate a cycle to see your phase timeline.")
            } else {
                let archiveSpans = vm.phaseSpansArchiveAverage
                let allSpans = spans + archiveSpans
                let maxDay = (allSpans.map(\.endDay).max() ?? 30) + 4
                let hasBoth = !spans.isEmpty && !archiveSpans.isEmpty

                Chart {
                    ForEach(spans) { span in
                        BarMark(xStart: .value("Start", span.startDay),
                                xEnd:   .value("End",   span.endDay),
                                y:      .value("Phase",  span.label),
                                height: .fixed(10))
                            .foregroundStyle(span.color)
                            .cornerRadius(4)
                    }
                    if spans.isEmpty {
                        ForEach(archiveSpans) { span in
                            BarMark(xStart: .value("Start", span.startDay),
                                    xEnd:   .value("End",   span.endDay),
                                    y:      .value("Phase",  span.label),
                                    height: .fixed(10))
                                .foregroundStyle(Color.gray.opacity(0.6))
                                .cornerRadius(4)
                        }
                    }
                }
                .chartXScale(domain: 1...maxDay)
                .chartXAxis {
                    AxisMarks(preset: .aligned) { value in
                        if let v = value.as(Int.self), v % 5 == 0 || v == 1 {
                            AxisValueLabel { Text("Day \(v)").font(.caption2) }
                        }
                        AxisGridLine()
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 120)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        if hasBoth, let plotFrameAnchor = proxy.plotFrame {
                            let plotFrame: CGRect = geo[plotFrameAnchor]
                            ForEach(archiveSpans) { span in
                                if let startX = proxy.position(forX: span.startDay),
                                   let endX   = proxy.position(forX: span.endDay),
                                   let midY   = proxy.position(forY: span.label) {
                                    let y = plotFrame.minY + midY - 8
                                    Path { path in
                                        path.move(to:    CGPoint(x: plotFrame.minX + startX, y: y))
                                        path.addLine(to: CGPoint(x: plotFrame.minX + endX,   y: y))
                                    }
                                    .stroke(Color.gray,
                                            style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                                }
                            }
                        }
                    }
                }

                if !spans.isEmpty {
                    FlowLayout(spacing: DS.Spacing.md) {
                        ForEach(spans) { span in
                            HStack(spacing: DS.Spacing.xs) {
                                RoundedRectangle(cornerRadius: 2).fill(span.color).frame(width: 10, height: 10)
                                Text("Day \(span.startDay)–\(span.endDay - 1)")
                                    .font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                            }
                        }
                    }
                    .padding(.top, DS.Spacing.xs)

                    if hasBoth {
                        HStack(spacing: DS.Spacing.xs) {
                            Path { path in
                                path.move(to:    CGPoint(x: 0, y: 5))
                                path.addLine(to: CGPoint(x: 14, y: 5))
                            }
                            .stroke(Color.gray, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .frame(width: 14, height: 10)
                            Text("Dashed = archived average")
                                .font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                        }
                        .padding(.top, DS.Spacing.xs)
                    }
                }
            }
        }
    }

    // MARK: - Chart 4: Cervical Mucus

    @ViewBuilder
    private func cervicalMucusChart(_ vm: InsightsViewModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Cervical Mucus")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("Consistency over cycle days - peak signals your fertile window.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)

            let data = vm.cervicalMucusData
            let archivedData = vm.archivedCervicalMucusAverageData
            if data.isEmpty && archivedData.isEmpty {
                placeholderCard(icon: "drop",
                    message: "Log cervical mucus tags to track your fertile window here.")
            } else {
                Chart {
                    ForEach(archivedData) { item in
                        LineMark(x: .value("Day", item.cycleDay), y: .value("Level", item.level))
                            .foregroundStyle(Color.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Day", item.cycleDay), y: .value("Level", item.level))
                            .foregroundStyle(Color.gray.opacity(0.3))
                            .symbolSize(40)
                    }
                    ForEach(data) { item in
                        LineMark(x: .value("Day", item.cycleDay), y: .value("Level", item.level))
                            .foregroundStyle(DS.Color.phase2Default)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Day", item.cycleDay), y: .value("Level", item.level))
                            .foregroundStyle(item.color)
                            .symbolSize(60)
                    }
                }
                .frame(height: 140)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .chartYScale(domain: 0...5)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4]) { value in
                        if let v = value.as(Int.self) {
                            AxisValueLabel { Text(vm.mucusLevelLabel(v)).font(.caption2) }
                            AxisGridLine()
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned) { value in
                        if let v = value.as(Int.self) {
                            AxisValueLabel { Text("Day \(v)").font(.caption2) }
                            AxisGridLine()
                        }
                    }
                }
                FlowLayout(spacing: DS.Spacing.md) {
                    ForEach([1, 2, 3, 4], id: \.self) { level in
                        HStack(spacing: DS.Spacing.xs) {
                            Circle().fill(vm.mucusColor(level)).frame(width: 8, height: 8)
                            Text(vm.mucusLevelLabel(level))
                                .font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                        }
                    }
                }
                .padding(.top, DS.Spacing.xs)
                if !data.isEmpty && !archivedData.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        Path { path in
                            path.move(to:    CGPoint(x: 0, y: 5))
                            path.addLine(to: CGPoint(x: 14, y: 5))
                        }
                        .stroke(Color.gray.opacity(0.3),
                                style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .frame(width: 14, height: 10)
                        Text("Dashed = archived average")
                            .font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                    }
                    .padding(.top, DS.Spacing.xs)
                } else if data.isEmpty && !archivedData.isEmpty {
                    Text("Showing archived cycle averages - log a current cycle to compare.")
                        .font(DS.Font.micro)
                        .foregroundColor(DS.Color.secondaryText)
                        .padding(.top, DS.Spacing.xs)
                }
            }
        }
    }

    // MARK: - Placeholder card

    private func placeholderCard(icon: String, message: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon).foregroundColor(DS.Color.secondaryText).frame(width: DS.Spacing.lg)
            Text(message).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.cardBackground)
        .cornerRadius(DS.Radius.chip)
    }
}

#Preview {
    InsightsView()
        .environmentObject(ArchivedDataStore())
        .environmentObject(EventStore(preview: true))
        .environmentObject(AppSettings())
}
