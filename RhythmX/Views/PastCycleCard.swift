//
//  PastCycleCard.swift
//

import SwiftUI

struct PastCycleCard: View {
    let block: ArchivedDataBlock
    @EnvironmentObject var appSettings: AppSettings
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var allEvents: [Event] { block.groupedEvents.flatMap { $0.events } }

    private var range: (start: Date, end: Date)? {
        guard let s = allEvents.map(\.date).min(), let e = allEvents.map(\.date).max() else { return nil }
        return (s, e)
    }

    private var lengthDays: Int {
        guard let r = range else { return 0 }
        return (Calendar.current.dateComponents([.day], from: r.start.startOfDay, to: r.end.startOfDay).day ?? 0) + 1
    }

    private var tagCount: Int { allEvents.reduce(0) { $0 + TagParser.split($1.tags).count } }

    private var sortedPhases: [ArchivedDataBlock.PhaseEvents] {
        block.groupedEvents.sorted {
            ($0.events.first?.date ?? .distantFuture) < ($1.events.first?.date ?? .distantFuture)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Button {
                if reduceMotion { expanded.toggle() } else { withAnimation { expanded.toggle() } }
            } label: {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack {
                        Text(title).font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                        Spacer()
                        Text("\(lengthDays) days · \(tagCount) tags")
                            .font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(DS.Font.micro).foregroundColor(DS.Color.tertiaryText)
                    }
                    PhaseStrip(segments: Event.EventType.allCases.map { phase in
                        (phase, block.groupedEvents.filter { $0.eventType == phase }.reduce(0) { $0 + $1.events.count })
                    })
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Collapse" : "Expand")

            if expanded {
                ForEach(sortedPhases, id: \.eventType.id) { phase in
                    let chips = TagParser.chips(from: phase.events.map(\.tags))
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        HStack(spacing: DS.Spacing.xs) {
                            MoonPhaseView(phase: phase.eventType.moonPhase,
                                          color: appSettings.phaseColor(for: phase.eventType), size: 14)
                            Text(phase.eventType.displayName)
                                .font(DS.Font.caption.weight(.semibold))
                                .foregroundColor(appSettings.phaseColor(for: phase.eventType))
                        }
                        if chips.isEmpty {
                            Text("No tags").font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                        } else {
                            FlowLayout(spacing: DS.Spacing.xs) {
                                ForEach(chips) { chip in
                                    Text(chip.count > 1 ? "\(chip.label) ×\(chip.count)" : chip.label)
                                        .font(DS.Font.micro)
                                        .padding(.vertical, 3).padding(.horizontal, DS.Spacing.sm)
                                        .background(DS.Color.accent.opacity(0.12))
                                        .foregroundColor(DS.Color.accent)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        NavigationLink("Edit tags") { PhaseTagsEditorView(phase: phase) }
                            .buttonStyle(.borderless)
                            .font(DS.Font.micro.weight(.medium))
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var title: String {
        guard let r = range else { return "Archived cycle" }
        return r.start.formatted(.dateTime.month(.abbreviated).day())
            + " – " + r.end.formatted(.dateTime.month(.abbreviated).day())
    }
}
