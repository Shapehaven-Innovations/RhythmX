//  WeekStripWidget.swift
//
//  Medium Plus widget: current phase and cycle day, days to the next period, and the seven days of this week
//  as dots tinted by phase with today outlined. Locked (no Plus, past the 3-day grace) it shows the upgrade
//  prompt and deep-links to the paywall.

import SwiftUI
import WidgetKit

struct WeekStripEntry: TimelineEntry {
    let date: Date
    let state: PlusWidgetState
    let snapshot: PhaseWidgetSnapshot
    let days: [WeekStripDay]

    /// Gallery preview: a follicular week around cycle day 8.
    static func sample(date: Date = Date()) -> WeekStripEntry {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: date.startOfDay) ?? date
        let events = (0..<14).map { offset in
            Event(eventType: offset < 5 ? .menstrual : (offset < 13 ? .follicular : .ovulation),
                  date: start.diff(numDays: offset), note: "")
        }
        return WeekStripEntry(date: date, state: .unlocked, snapshot: .sample,
                              days: PhaseWidgetSnapshot.weekDays(events: events, today: date))
    }
}

struct WeekStripTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekStripEntry { .sample() }

    func getSnapshot(in context: Context, completion: @escaping (WeekStripEntry) -> Void) {
        completion(context.isPreview ? .sample() : Self.entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekStripEntry>) -> Void) {
        let now = Date()
        let horizon = now.startOfDay.diff(numDays: 7)
        // One entry per day; `PlusWidgetState.timeline` adds the entry at expiry plus grace that flips the
        // widget to the upgrade prompt without waiting for a reload.
        let slots = PlusWidgetState.timeline(base: (0..<7).map { $0 == 0 ? now : now.startOfDay.diff(numDays: $0) },
                                             now: now, horizon: horizon,
                                             entitlement: Entitlement.load(from: AppGroup.defaults))
        completion(Timeline(entries: slots.map { Self.entry(at: $0.date) }, policy: .after(horizon)))
    }

    static func entry(at date: Date, defaults: UserDefaults = AppGroup.defaults) -> WeekStripEntry {
        let state = PlusWidgetState.make(entitlement: Entitlement.load(from: defaults), now: date)
        guard state == .unlocked else {
            return WeekStripEntry(date: date, state: .locked, snapshot: PhaseWidgetSnapshot(phase: nil, cycleDay: nil, daysUntilNext: nil), days: [])
        }
        let events = PhaseWidgetSnapshot.loadEvents(from: defaults)
        return WeekStripEntry(date: date, state: .unlocked,
                              snapshot: PhaseWidgetSnapshot.load(defaults: defaults, today: date),
                              days: PhaseWidgetSnapshot.weekDays(events: events, today: date))
    }
}

struct WeekStripWidget: Widget {
    let kind = "WeekStripWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeekStripTimelineProvider()) { entry in
            WeekStripWidgetView(entry: entry)
                .containerBackground(DS.Color.pageBackground, for: .widget)
        }
        .configurationDisplayName("Week Strip")
        .description("This week at a glance: phase, cycle day and next period. RhythmX Plus.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Views

struct WeekStripWidgetView: View {
    let entry: WeekStripEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let settings = AppSettings()

    var body: some View {
        switch entry.state {
        case .locked:
            PlusLockedWidgetView(detail: "Phase, cycle day and this week's days.")
        case .unlocked:
            unlocked
        }
    }

    private var snap: PhaseWidgetSnapshot { entry.snapshot }

    private var phaseColor: Color {
        snap.phase.map { settings.phaseColor(for: $0) } ?? DS.Color.tertiaryText
    }

    private func days(_ n: Int) -> String { "\(n) day\(n == 1 ? "" : "s")" }

    private var periodLine: String? {
        if let o = snap.overdueDays { return "Period \(days(o)) late" }
        guard let d = snap.daysUntilNext else { return nil }
        switch d {
        case 0: return "Period expected today"
        case 1: return "Period tomorrow"
        default: return "Period in \(days(d))"
        }
    }

    private var unlocked: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                MoonPhaseView(phase: (snap.phase ?? .ovulation).moonPhase, color: phaseColor, isActive: snap.phase != nil, size: 30)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let day = snap.cycleDay {
                        Text("Day \(day)")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(DS.Color.primaryText)
                    } else {
                        Text("No active cycle")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(DS.Color.primaryText)
                    }
                    Text(snap.phase?.displayName ?? (snap.cycleDay == nil ? "Open RhythmX to start." : "No entry today"))
                        .font(.caption.weight(.medium))
                        .foregroundColor(snap.phase == nil ? DS.Color.secondaryText : phaseColor)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let line = periodLine {
                    Text(line)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(settings.phaseColor(for: .menstrual))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            strip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(Array(entry.days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 5) {
                    Text(weekdayLetter(day.date))
                        .font(.caption2.weight(day.isToday ? .bold : .regular))
                        .foregroundColor(day.isToday ? DS.Color.primaryText : DS.Color.secondaryText)
                    ZStack {
                        Circle()
                            .fill(day.phase.map { settings.phaseColor(for: $0) } ?? DS.Color.tertiaryText.opacity(0.25))
                            .frame(width: dotSize, height: dotSize)
                            .widgetAccentable(day.isToday)
                        if day.isToday {
                            Circle()
                                .stroke(DS.Color.primaryText, lineWidth: 2)
                                .frame(width: dotSize + 6, height: dotSize + 6)
                        }
                    }
                    .frame(height: dotSize + 6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var dotSize: CGFloat { dynamicTypeSize.isAccessibilitySize ? 10 : 14 }

    private func weekdayLetter(_ date: Date) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let index = Calendar.current.component(.weekday, from: date) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let day = snap.cycleDay { parts.append("Cycle day \(day)") }
        if let phase = snap.phase { parts.append(phase.displayName) }
        if let line = periodLine { parts.append(line) }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        let week = entry.days.map { day -> String in
            let name = formatter.string(from: day.date)
            let phase = day.phase.map { $0.rawValue.capitalized } ?? "no entry"
            return day.isToday ? "\(name), today, \(phase)" : "\(name), \(phase)"
        }
        if !week.isEmpty { parts.append("This week: " + week.joined(separator: "; ")) }
        return parts.isEmpty ? "No active cycle. Open RhythmX to start." : parts.joined(separator: ". ")
    }
}

/// The upgrade prompt both Plus widgets show when Plus is off. The whole widget links to the paywall.
struct PlusLockedWidgetView: View {
    var detail: String
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MoonPhaseView(phase: .full, color: DS.Color.moon, isActive: true, size: family == .systemSmall ? 26 : 30)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(PlusWidgetState.lockedTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DS.Color.primaryText)
            Text(PlusWidgetState.lockedSubtitle)
                .font(.caption.weight(.medium))
                .foregroundColor(DS.Color.accent)
            if family != .systemSmall {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DS.Color.secondaryText)
                    .lineLimit(2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(PlusWidgetState.paywallURL)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(PlusWidgetState.lockedTitle). \(PlusWidgetState.lockedSubtitle). \(detail)")
        .accessibilityHint("Opens RhythmX Plus in the app")
    }
}
