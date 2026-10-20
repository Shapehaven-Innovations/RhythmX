//  EventsListView.swift

import SwiftUI

/// The two segments under the Tags title. "Tags" is the phase cards; "Patterns" is TagPatternsView.
enum TagsSegment: String, CaseIterable, Identifiable {
    case tags = "Tags"
    case patterns = "Patterns"
    var id: String { rawValue }
}

struct EventsListView: View {
    /// Owned by the tab view so a weekly check-in tap can land on Patterns before this tab has ever been shown.
    @Binding var segment: TagsSegment
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var appSettings: AppSettings
    @State private var showTagForm = false
    @State private var editingPhase: Event.EventType? = nil
    @State private var pendingRemoval: (chip: TagChip, phase: Event.EventType)? = nil

    init(segment: Binding<TagsSegment>) {
        _segment = segment
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TagsSegmentPicker(segment: $segment)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.sm)
                switch segment {
                case .tags:
                    if myEvents.cycleEvents.isEmpty { emptyState } else { phaseCards }
                case .patterns:
                    TagPatternsView()
                }
            }
            .themedPage()
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showTagForm = true } label: {
                        Image(systemName: "plus.circle.fill").imageScale(.large)
                    }
                    .accessibilityLabel("Add tag")
                    // Menopause needs no cycle: the form creates a carrier event for the day.
                    .disabled(appSettings.trackingMode != .menopause && myEvents.cycleEvents.isEmpty)
                }
            }
            .sheet(isPresented: $showTagForm) { TagFormView() }
            .sheet(item: $editingPhase) { PhaseTagEditorSheet(phase: $0) }
            .confirmationDialog(
                pendingRemoval.map { "Remove \"\($0.chip.label)\" from the \($0.phase.rawValue) phase?" } ?? "",
                isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let p = pendingRemoval { myEvents.removeTag(p.chip.raw, in: p.phase) }
                    pendingRemoval = nil
                }
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
            }
        }
    }

    private var phaseCards: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                ForEach(Event.EventType.allCases) { phase in
                    let phaseEvents = myEvents.events.filter { $0.eventType == phase }.sorted { $0.date < $1.date }
                    if let first = phaseEvents.first, let last = phaseEvents.last {
                        phaseCard(phase: phase, events: phaseEvents, start: first.date, end: last.date)
                    }
                }
            }
            .padding(DS.Spacing.md)
        }
    }

    private func phaseCard(phase: Event.EventType, events: [Event], start: Date, end: Date) -> some View {
        let chips = TagParser.chips(from: events.map(\.tags))
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                MoonPhaseView(phase: phase.moonPhase, color: appSettings.phaseColor(for: phase), size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.displayName).font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                    Text(start.formatted(date: .abbreviated, time: .omitted) + " – " + end.formatted(date: .abbreviated, time: .omitted))
                        .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                }
                Spacer()
                Button { editingPhase = phase } label: {
                    Image(systemName: "pencil.circle").imageScale(.large)
                }
                .accessibilityLabel("Edit \(phase.displayName) tags")
            }
            if chips.isEmpty {
                Text("No tags yet. Tap + to add one.")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
            } else {
                FlowLayout(spacing: DS.Spacing.xs) {
                    ForEach(chips) { chip in
                        ChipButton(title: chip.count > 1 ? "\(chip.label) ×\(chip.count)" : chip.label) {
                            pendingRemoval = (chip, phase)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            MoonPhaseView(phase: .crescent, color: DS.Color.moon, isActive: true, size: 56)
            Text("No Events Yet")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
            Text("Go to Cycles to start your first cycle, then log tags here.")
                .font(DS.Font.label)
                .foregroundColor(DS.Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xl)
            Spacer()
        }
    }
}

// MARK: - Tags | Patterns pill
/// Same pill style as ModeSwitcher on Insights, for the two Tags segments.
private struct TagsSegmentPicker: View {
    @Binding var segment: TagsSegment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection

    var body: some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 2))
            : AnyLayout(HStackLayout(spacing: 2))) {
            ForEach(TagsSegment.allCases) { candidate in
                option(candidate)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                .fill(Color(UIColor.tertiarySystemFill))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tags view")
        .accessibilityValue(segment.rawValue)
    }

    private func option(_ candidate: TagsSegment) -> some View {
        let isSelected = candidate == segment
        return Button {
            guard !isSelected else { return }
            if reduceMotion {
                segment = candidate
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { segment = candidate }
            }
        } label: {
            Text(candidate.rawValue)
                .font(DS.Font.label.weight(isSelected ? .semibold : .medium))
                .foregroundColor(DS.Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, DS.Spacing.sm)
                .padding(.horizontal, DS.Spacing.xs)
                .frame(maxWidth: .infinity)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: DS.Radius.button - 2, style: .continuous)
                            .fill(DS.Color.cardBackground)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                            .matchedGeometryEffect(id: "selected", in: selection)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Phase Tag Editor Sheet
private struct PhaseTagEditorSheet: View {
    let phase: Event.EventType
    @EnvironmentObject var myEvents: EventStore
    @Environment(\.dismiss) var dismiss

    @State private var editingTags: [String: String] = [:]

    private var phaseEvents: [Event] {
        myEvents.cycleEvents.filter { $0.eventType == phase }.sorted { $0.date < $1.date }
    }

    private func tagBinding(for event: Event) -> Binding<String> {
        Binding(
            get: { editingTags[event.id] ?? event.tags },
            set: { editingTags[event.id] = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Category:Value, comma-separated - e.g. Symptom:Cramps")
                        .font(DS.Font.micro)
                        .foregroundColor(DS.Color.secondaryText)
                        .listRowBackground(Color.clear)
                }

                ForEach(phaseEvents) { event in
                    Section {
                        TextField("Tags", text: tagBinding(for: event), axis: .vertical)
                            .lineLimit(2...4)
                            .font(DS.Font.caption)
                            .foregroundColor(DS.Color.primaryText)
                    } header: {
                        Text(event.date.formatted(date: .abbreviated, time: .omitted))
                            .font(DS.Font.micro)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DS.Color.pageBackground)
            .navigationTitle("Edit \(phase.displayName) Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        for event in phaseEvents {
                            if let newTags = editingTags[event.id] {
                                var updated = event
                                updated.tags = newTags
                                myEvents.update(updated)
                            }
                        }
                        dismiss()
                    }
                    .font(DS.Font.label.weight(.semibold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var segment: TagsSegment = .tags
    EventsListView(segment: $segment)
        .environmentObject(EventStore(preview: true))
        .environmentObject(ArchivedDataStore())
        .environmentObject(AppSettings())
}
