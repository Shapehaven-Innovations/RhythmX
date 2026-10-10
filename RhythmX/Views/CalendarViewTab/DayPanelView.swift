//  DayPanelView.swift

import SwiftUI

struct DayPanelView: View {
    let date: Date
    @EnvironmentObject var eventStore: EventStore
    @State private var showTagForm = false

    private var dayEvents: [Event] {
        eventStore.events.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(date.formatted(date: .complete, time: .omitted))
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)

            if dayEvents.isEmpty {
                Text("No cycle event on this day.")
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.secondaryText)
            } else {
                ForEach(dayEvents) { event in
                    ListViewRow(event: event)
                        .contextMenu {
                            Button(role: .destructive) { eventStore.delete(event) } label: {
                                Label("Delete event", systemImage: "trash")
                            }
                        }
                }
                PrimaryButton(title: "Add tag") { showTagForm = true }
            }
        }
        .cardStyle()
        .sheet(isPresented: $showTagForm) { TagFormView(initialDate: date) }
    }
}
