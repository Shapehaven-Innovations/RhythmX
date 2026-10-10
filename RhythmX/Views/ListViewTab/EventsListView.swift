//  EventsListView.swift

import SwiftUI

struct EventsListView: View {
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var appSettings: AppSettings
    @State private var showTagForm = false
    @State private var editingPhase: Event.EventType? = nil
    @State private var pendingRemoval: (chip: TagChip, phase: Event.EventType)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if myEvents.events.isEmpty { emptyState } else { phaseCards }
            }
            .background(DS.Color.pageBackground.ignoresSafeArea())
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showTagForm = true } label: {
                        Image(systemName: "plus.circle.fill").imageScale(.large)
                    }
                    .accessibilityLabel("Add tag")
                    .disabled(myEvents.events.isEmpty)
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

// MARK: - Phase Tag Editor Sheet
private struct PhaseTagEditorSheet: View {
    let phase: Event.EventType
    @EnvironmentObject var myEvents: EventStore
    @Environment(\.dismiss) var dismiss

    @State private var editingTags: [String: String] = [:]

    private var phaseEvents: [Event] {
        myEvents.events.filter { $0.eventType == phase }.sorted { $0.date < $1.date }
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
    EventsListView()
        .environmentObject(EventStore(preview: true))
}
