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

    // Past Cycles shows every mode; nil is the "All" filter.
    @State private var modeFilter: TrackingMode? = nil

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
        .themedPage()
        .safeAreaInset(edge: .top, spacing: 0) {
            ArchiveModeFilterPill(filter: $modeFilter)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.pageBackground)
        }
        .overlay {
            if archivedDataStore.archivedBlocks.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    MoonPhaseView(phase: .waning, color: DS.Color.moon, isActive: true, size: 48)
                    Text("No past cycles yet")
                        .font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                    Text("Log your next period from Today or Cycles and the finished cycle will appear here.")
                        .font(DS.Font.label).foregroundColor(DS.Color.secondaryText)
                        .multilineTextAlignment(.center).padding(.horizontal, DS.Spacing.xl)
                }
            } else if let modeFilter, searchText.isEmpty, filteredArchivedData.isEmpty {
                Text("No \(modeFilter.title) cycles yet")
                    .font(DS.Font.label).foregroundColor(DS.Color.secondaryText)
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

    /// Blocks for the selected mode, narrowed to the events whose tags match `searchText`.
    private var filteredArchivedData: [ArchivedDataBlock] {
        archivedDataStore.blocks(matching: modeFilter, search: searchText)
    }
}

/// The Past Cycles filter: All, Cycle, Planning, Menopause, in the same pill style as the Insights mode switcher.
private struct ArchiveModeFilterPill: View {
    @Binding var filter: TrackingMode?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection

    private var options: [TrackingMode?] { [nil] + TrackingMode.allCases.map { Optional($0) } }

    var body: some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 2))
            : AnyLayout(HStackLayout(spacing: 2))) {
            ForEach(options, id: \.self) { candidate in
                segment(candidate)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                .fill(Color(UIColor.tertiarySystemFill))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show cycles from")
        .accessibilityValue(title(for: filter))
    }

    private func title(for candidate: TrackingMode?) -> String { candidate?.title ?? "All" }

    private func segment(_ candidate: TrackingMode?) -> some View {
        let isSelected = candidate == filter
        return Button {
            guard !isSelected else { return }
            if reduceMotion {
                filter = candidate
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { filter = candidate }
            }
        } label: {
            Text(title(for: candidate))
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
        .accessibilityLabel(title(for: candidate))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
