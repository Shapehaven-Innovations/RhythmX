//  PhaseCalendarView.swift

import SwiftUI

struct PhaseCalendarView: View {
    @EnvironmentObject var eventStore: EventStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var fertileStore: FertileStore
    @Binding var selectedDate: Date?
    let predictedStart: Date?
    @State private var month = CalendarMonthModel(containing: Date())

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack {
                Text(month.title)
                    .font(DS.Font.sectionHeader)
                    .foregroundColor(DS.Color.primaryText)
                Spacer()
                Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("Previous month")
                Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("Next month")
            }
            HStack(spacing: 4) {
                ForEach(Array(month.weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(month.cells.enumerated()), id: \.offset) { _, cell in
                    if let day = cell {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .cardStyle()
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let phase = CalendarPhaseLookup.phase(on: day.date, events: eventStore.cycleEvents)
        let color = phase.map { appSettings.phaseColor(for: $0) }
        let isToday = Calendar.current.isDateInToday(day.date)
        let isSelected = selectedDate.map { Calendar.current.isDate($0, inSameDayAs: day.date) } ?? false
        let fertile = fertileStore.isFertile(day.date, events: eventStore.cycleEvents)
        let predicted = phase == nil && day.date.startOfDay >= Date().startOfDay && CalendarPhaseLookup.isPredictedPeriod(day.date, start: predictedStart)

        return Button {
            selectedDate = day.date
        } label: {
            Text("\(day.number)")
                .font(DS.Font.label.weight(isToday ? .bold : .regular))
                .foregroundColor(isToday ? DS.Color.onAccent : DS.Color.primaryText)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    Circle().fill(isToday ? (color ?? DS.Color.accent) : (color?.opacity(0.22) ?? .clear))
                )
                .overlay(alignment: .bottom) {
                    if fertile {
                        Capsule()
                            .fill(isToday ? DS.Color.onAccent : appSettings.phaseColor(for: .ovulation))
                            .frame(width: 14, height: 3)
                            .padding(.bottom, 4)
                    }
                }
                .overlay(
                    Circle().strokeBorder(
                        predicted ? appSettings.phaseColor(for: .menstrual) : (isSelected ? DS.Color.accent : .clear),
                        style: StrokeStyle(lineWidth: isSelected ? 2 : 1.5, dash: predicted && !isSelected ? [3, 2] : [])
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(day.date.formatted(date: .complete, time: .omitted))"
            + (phase.map { ", \($0.displayName)" } ?? "")
            + (predicted ? ", predicted period" : "")
            + (fertile ? ", fertile window" : "")
        )
    }
}
