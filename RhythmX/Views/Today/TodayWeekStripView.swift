//  TodayWeekStripView.swift
//  This week on Today: phase-coloured dots, the estimated period days dashed, today filled with the accent.
//  Menopause shows only how much was logged each day.

import SwiftUI

struct TodayWeekStripView: View {
    let days: [TodayStripDay]
    let mode: TrackingMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                column(day).frame(maxWidth: .infinity)
            }
        }
        // Seven fixed columns: capped so they never overflow; VoiceOver reads each day in full.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("This week")
    }

    private var peakCount: Int { max(days.map(\.menopauseCount).max() ?? 0, 1) }

    private func column(_ day: TodayStripDay) -> some View {
        VStack(spacing: 5) {
            Text(day.isToday ? "TODAY" : weekdayLetter(day.date))
                .font(.caption2.weight(.semibold))
                .foregroundColor(DS.Color.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.body.weight(day.isToday || day.isPredictedPeriod ? .bold : .regular).monospacedDigit())
                .foregroundColor(day.isToday ? DS.Color.onAccent : DS.Color.primaryText)
                .frame(width: 38, height: 38)
                .background {
                    if day.isToday {
                        Circle().fill(DS.Color.accent)
                    } else if day.isPredictedPeriod {
                        Circle().strokeBorder(DS.Color.phase1, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                }
            dot(day).frame(width: 6, height: 6)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(day))
    }

    @ViewBuilder
    private func dot(_ day: TodayStripDay) -> some View {
        if mode == .menopause {
            Circle().fill(DS.Color.accent.opacity(day.menopauseCount == 0 ? 0 : 0.3 + 0.7 * Double(day.menopauseCount) / Double(peakCount)))
        } else if let phase = day.phase {
            Circle().fill(phase.defaultPhaseColor)
        } else if day.isPredictedPeriod {
            Circle().strokeBorder(DS.Color.phase1, lineWidth: 1.2)
        } else {
            Color.clear
        }
    }

    private func weekdayLetter(_ date: Date) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return symbols[(Calendar.current.component(.weekday, from: date) - 1) % symbols.count]
    }

    private func accessibilityLabel(_ day: TodayStripDay) -> String {
        var parts = [day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if day.isToday { parts.append("today") }
        if mode == .menopause {
            if day.menopauseCount > 0 { parts.append(day.menopauseCount == 1 ? "1 tag logged" : "\(day.menopauseCount) tags logged") }
        } else if let phase = day.phase {
            parts.append(phase.displayName)
        } else if day.isPredictedPeriod {
            parts.append("estimated period")
        }
        return parts.joined(separator: ", ")
    }
}
