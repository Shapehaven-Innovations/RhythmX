//
//  PhaseTagsEditorView.swift
//  RhythmX
//
//  Created by user on 3/22/25.
//


//
//  PhaseTagsEditorView.swift
//  Rhythm
//

import SwiftUI

struct PhaseTagsEditorView: View {
    let phase: ArchivedDataBlock.PhaseEvents

    // We need access to the archived store to update event tags
    @EnvironmentObject var archivedDataStore: ArchivedDataStore

    // A local copy of the events so the user can edit them freely
    @State private var localEvents: [Event]

    // For dismissing ourselves after “Save”
    @Environment(\.dismiss) var dismiss

    init(phase: ArchivedDataBlock.PhaseEvents) {
        self.phase = phase
        // Initialize localEvents with a copy of the events in this phase
        _localEvents = State(initialValue: phase.events)
    }

    var body: some View {
        List {
            // For each event in the local array, show a multiline text field
            ForEach($localEvents) { $event in
                Section {
                    // iOS 16+ multiline text field
                    if #available(iOS 16.0, *) {
                        TextField("Tags", text: $event.tags, axis: .vertical)
                            .lineLimit(3)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        // iOS 15 fallback
                        TextEditor(text: $event.tags)
                            .frame(minHeight: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary, lineWidth: 1)
                            )
                    }
                } header: {
                    // Display the date as a header
                    Text(event.date.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.Color.pageBackground)
        .navigationTitle("Edit \(phase.eventType.rawValue.capitalized) Tags")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // Update each event’s tags in the archived store
                    for e in localEvents {
                        archivedDataStore.updateArchivedEventTag(
                            eventId: e.id,
                            newTags: e.tags
                        )
                    }
                    // Dismiss the view
                    dismiss()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
}
