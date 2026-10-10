//
//  ArchivedDataView.swift
//  Rhythm
//

import SwiftUI

struct ArchivedDataView: View {
    @EnvironmentObject var archivedDataStore: ArchivedDataStore

    // For the confirmation alert to clear all
    @State private var showDeleteConfirmation = false

    // For searching tags
    @State private var searchText = ""

    var body: some View {
        List {
            ForEach(filteredArchivedData) { block in
                PastCycleCard(block: block)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: DS.Spacing.xs, leading: DS.Spacing.md, bottom: DS.Spacing.xs, trailing: DS.Spacing.md))
                    .swipeActions(allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            archivedDataStore.deleteArchivedBlock(id: block.id)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.Color.pageBackground.ignoresSafeArea())
        .overlay {
            if archivedDataStore.archivedBlocks.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    MoonPhaseView(phase: .waning, color: DS.Color.moon, isActive: true, size: 48)
                    Text("No past cycles yet")
                        .font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                    Text("Archive a cycle from Cycles and it will appear here.")
                        .font(DS.Font.label).foregroundColor(DS.Color.secondaryText)
                        .multilineTextAlignment(.center).padding(.horizontal, DS.Spacing.xl)
                }
            }
        }
        .navigationTitle("Past Cycles")
        .searchable(text: $searchText, prompt: "Search tags")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) { showDeleteConfirmation = true } label: {
                        Label("Clear all past cycles", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(archivedDataStore.archivedBlocks.isEmpty)
                .accessibilityLabel("More")
            }
        }
        .alert("Delete All Archived Data?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { archivedDataStore.clearAllArchivedData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action will permanently remove all archived data.")
        }
    }

    /// Filter archived data based on `searchText` in the `tags`.
    private var filteredArchivedData: [ArchivedDataBlock] {
        let allBlocks = archivedDataStore.archivedBlocks
        guard !searchText.isEmpty else { return allBlocks }

        // Return only blocks that contain phases with events matching the search text
        return allBlocks.compactMap { block in
            let filteredPhases = block.groupedEvents.compactMap { phase -> ArchivedDataBlock.PhaseEvents? in
                let matchingEvents = phase.events.filter {
                    $0.tags.range(of: searchText, options: .caseInsensitive) != nil
                }
                guard !matchingEvents.isEmpty else { return nil }
                return ArchivedDataBlock.PhaseEvents(eventType: phase.eventType, events: matchingEvents)
            }
            guard !filteredPhases.isEmpty else { return nil }

            return ArchivedDataBlock(
                id: block.id,
                date: block.date,
                groupedEvents: filteredPhases
            )
        }
    }
}

