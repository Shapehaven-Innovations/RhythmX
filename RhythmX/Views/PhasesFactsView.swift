//  PhasesFactsView.swift

import SwiftUI

struct PhasesFactsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @State private var selected: Event.EventType = .menstrual
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var entry: PhaseGuideEntry {
        let index = Event.EventType.allCases.firstIndex(of: selected) ?? 0
        return PhaseGuideParser.parse(PhaseGuideContent.raw[index])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                if let guide = ModeGuideContent.guide(for: appSettings.trackingMode) {
                    ModeGuideSection(guide: guide)
                    Text("Cycle phases")
                        .font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DS.Spacing.sm)
                        .accessibilityAddTraits(.isHeader)
                }
                HStack {
                    ForEach(Event.EventType.allCases) { phase in
                        Button { if reduceMotion { selected = phase } else { withAnimation { selected = phase } } } label: {
                            VStack(spacing: DS.Spacing.xs) {
                                MoonPhaseView(phase: phase.moonPhase,
                                              color: appSettings.phaseColor(for: phase),
                                              isActive: phase == selected, size: 30)
                                Text(phase.rawValue.capitalized)
                                    .font(DS.Font.micro)
                                    .fontWeight(phase == selected ? .bold : .regular)
                                    .foregroundColor(phase == selected ? DS.Color.primaryText : DS.Color.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(phase.displayName)
                        .accessibilityAddTraits(phase == selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, DS.Spacing.sm)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(entry.heading).font(DS.Font.displayTitle).foregroundColor(DS.Color.primaryText)
                    ForEach(entry.timing, id: \.self) { line in
                        boldTextBeforeColon(line).foregroundColor(DS.Color.secondaryText)
                    }
                }
                .cardStyle()

                ForEach(entry.sections) { section in
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(section.title).font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                        ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                            boldTextBeforeColon(line)
                        }
                    }
                    .cardStyle()
                }

                Text("Disclaimer: The information above is for your general knowledge and educational purposes – not a substitute for professional medical advice! Always consult a doctor if you have any health concerns. Keep grooving, stay informed, and remember: your body is unique, and we're just here to help you find your rhythm.")
                    .font(DS.Font.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(DS.Color.secondaryText)
                    .padding(.horizontal, DS.Spacing.md)
            }
            .padding(DS.Spacing.md)
        }
        .themedPage()
        .navigationTitle("Your Phases")
    }

    /// Bold everything before the first colon (if any).
    @ViewBuilder
    private func boldTextBeforeColon(_ line: String) -> some View {
        if let colonIndex = line.firstIndex(of: ":") {
            let key = line[..<colonIndex]
            let value = line[line.index(after: colonIndex)...]
            Text(.init("**\(key):**\(value)")).font(DS.Font.body)
        } else {
            Text(line).font(DS.Font.body)
        }
    }
}

/// Planning or Menopause: the mode label, an intro, and one card per topic with the tags to log for it.
private struct ModeGuideSection: View {
    let guide: ModeGuide

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Label(guide.modeLabel, systemImage: guide.mode == .planning ? TagCategory.planning.symbolName : TagCategory.menopause.symbolName)
                    .font(DS.Font.caption.weight(.semibold))
                    .foregroundColor(DS.Color.onAccent)
                    .padding(.horizontal, DS.Spacing.sm).padding(.vertical, DS.Spacing.xs)
                    .background(Capsule().fill(DS.Color.accent))
                Text(guide.title).font(DS.Font.displayTitle).foregroundColor(DS.Color.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(guide.intro).font(DS.Font.body).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .cardStyle()

            ForEach(guide.topics) { topic in
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Label(topic.title, systemImage: topic.symbolName)
                        .font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text(topic.text).font(DS.Font.body).foregroundColor(DS.Color.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Suggested tags").font(DS.Font.caption.weight(.semibold)).foregroundColor(DS.Color.secondaryText)
                    FlowLayout(spacing: DS.Spacing.sm) {
                        ForEach(topic.tags, id: \.self) { tag in
                            Label(tag.value, systemImage: tag.category.symbolName)
                                .font(DS.Font.caption.weight(.medium))
                                .foregroundColor(DS.Color.accent)
                                .padding(.horizontal, DS.Spacing.sm).padding(.vertical, 6)
                                .background(Capsule().fill(DS.Color.accent.opacity(0.10)))
                                .accessibilityLabel("\(tag.value), under \(tag.category.rawValue)")
                        }
                    }
                }
                .cardStyle()
            }

            Text(guide.disclaimer)
                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    NavigationStack { PhasesFactsView() }.environmentObject(AppSettings())
}
