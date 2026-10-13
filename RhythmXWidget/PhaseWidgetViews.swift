import SwiftUI
import WidgetKit

struct PhaseWidgetView: View {
    let entry: PhaseEntry
    @Environment(\.widgetFamily) private var family
    private let settings = AppSettings()

    private var snap: PhaseWidgetSnapshot { entry.snapshot }
    private var color: Color {
        snap.phase.map { settings.phaseColor(for: $0) } ?? DS.Color.tertiaryText
    }

    var body: some View {
        Group {
            if snap.isActive {
                if family == .systemMedium { medium } else { small }
            } else {
                inactive
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let day = snap.cycleDay { parts.append("Cycle day \(day)") }
        if let phase = snap.phase { parts.append(phase.displayName) }
        if let d = snap.daysUntilNext { parts.append(d == 0 ? "Next period expected today" : "Next period in \(d) day\(d == 1 ? "" : "s")") }
        if let o = snap.overdueDays { parts.append("Period \(o) day\(o == 1 ? "" : "s") late") }
        return parts.isEmpty ? "No active cycle. Open RhythmX to start." : parts.joined(separator: ", ")
    }

    /// Shown when no cycle day applies: due today, overdue, upcoming (from past cycles), or nothing logged.
    private var inactiveCopy: (title: String, subtitle: String) {
        if let o = snap.overdueDays { return ("Period \(o) day\(o == 1 ? "" : "s") late", "Open RhythmX to log.") }
        if let d = snap.daysUntilNext {
            return d == 0 ? ("Period expected today", "Open RhythmX to log.")
                          : ("Next period in \(d) day\(d == 1 ? "" : "s")", "Open RhythmX to log.")
        }
        return ("No active cycle", "Open RhythmX to start.")
    }

    private var moon: some View {
        MoonPhaseView(phase: (snap.phase ?? .ovulation).moonPhase, color: color, isActive: snap.phase != nil, size: 36)
            .padding(6)
            .widgetAccentable()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Day \(snap.cycleDay ?? 0)")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundColor(DS.Color.primaryText)
                .minimumScaleFactor(0.8)
            if let phase = snap.phase {
                Text(phase.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundColor(color)
            } else {
                Text("No entry today")
                    .font(.caption.weight(.medium))
                    .foregroundColor(DS.Color.secondaryText)
            }
        }
        .lineLimit(1)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            moon
            Spacer(minLength: 0)
            header
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                moon
                Spacer(minLength: 0)
                header
            }
            VStack(alignment: .leading, spacing: 0) {
                if let d = snap.daysUntilNext {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT PERIOD")
                            .font(.caption2.weight(.semibold))
                            .tracking(0.8)
                            .foregroundColor(DS.Color.secondaryText)
                        Text("In \(d) day\(d == 1 ? "" : "s")")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundColor(settings.phaseColor(for: .menstrual))
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                    }
                    .padding(.top, 8)
                }
                Spacer(minLength: 0)
                phaseStrip
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private var phaseStrip: some View {
        HStack(spacing: 4) {
            ForEach(Event.EventType.allCases) { p in
                Capsule()
                    .fill(settings.phaseColor(for: p).opacity(p == snap.phase ? 1 : 0.25))
                    .frame(height: 6)
                    .widgetAccentable(p == snap.phase)
            }
        }
        .accessibilityHidden(true)
    }

    private var inactive: some View {
        VStack(alignment: .leading, spacing: 6) {
            moon
            Spacer(minLength: 0)
            Text(inactiveCopy.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DS.Color.primaryText)
            Text(inactiveCopy.subtitle)
                .font(.caption)
                .foregroundColor(DS.Color.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
