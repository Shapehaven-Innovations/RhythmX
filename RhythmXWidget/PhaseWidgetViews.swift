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
    private var periodColor: Color { settings.phaseColor(for: .menstrual) }

    var body: some View {
        Group {
            if snap.isActive {
                switch family {
                case .systemLarge: large
                case .systemMedium: medium
                default: small
                }
            } else {
                inactive
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Copy

    private func days(_ n: Int) -> String { "\(n) day\(n == 1 ? "" : "s")" }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let day = snap.cycleDay { parts.append("Cycle day \(day)") }
        if let phase = snap.phase { parts.append(phase.displayName) }
        if let d = snap.daysUntilNext { parts.append(d == 0 ? "Next period expected today" : "Next period in \(days(d))") }
        if let p = snap.nextPhase, let d = snap.daysUntilNextPhase, family == .systemLarge {
            parts.append("\(p.displayName) starts in \(days(d))")
        }
        if snap.isFertileToday {
            parts.append((snap.fertileEndsIn ?? 0) == 0 ? "Fertile window ends today" : "Fertile window, ends in \(days(snap.fertileEndsIn ?? 0))")
        } else if let s = snap.fertileStartsIn, family != .systemSmall {
            parts.append("Fertile window starts in \(days(s))")
        }
        if let o = snap.overdueDays { parts.append("Period \(days(o)) late") }
        return parts.isEmpty ? "No active cycle. Open RhythmX to start." : parts.joined(separator: ", ")
    }

    /// Small widget period line, e.g. "Period in 20 days" / "Period tomorrow".
    private func periodLine(_ d: Int) -> String {
        switch d {
        case 0: return "Period today"
        case 1: return "Period tomorrow"
        default: return "Period in \(d) days"
        }
    }

    // MARK: - Pieces

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

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.18)))
    }

    /// Always shows the countdown; it becomes a highlighted badge within 3 days of the period.
    @ViewBuilder
    private var smallPeriodLine: some View {
        if let d = snap.daysUntilNext {
            if snap.isPeriodSoon {
                badge(periodLine(d), tint: periodColor)
            } else {
                Text(periodLine(d))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(periodColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    @ViewBuilder
    private var fertileChip: some View {
        if snap.isFertileToday {
            badge("Fertile", tint: settings.phaseColor(for: .ovulation))
        }
    }

    @ViewBuilder
    private var mediumFertileLine: some View {
        if snap.isFertileToday || snap.fertileStartsIn != nil {
            let tint = settings.phaseColor(for: .ovulation)
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(mediumFertileText)
                    .font(.caption.weight(.medium))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.bottom, 8)
        }
    }

    private var mediumFertileText: String {
        if snap.isFertileToday {
            let e = snap.fertileEndsIn ?? 0
            return e == 0 ? "Fertile · ends today" : "Fertile · ends in \(days(e))"
        }
        return "Fertile in \(days(snap.fertileStartsIn ?? 0))"
    }

    @ViewBuilder
    private var fertileBanner: some View {
        let tint = settings.phaseColor(for: .ovulation)
        if snap.isFertileToday || snap.fertileStartsIn != nil {
            HStack {
                Text("FERTILE WINDOW")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundColor(DS.Color.secondaryText)
                Spacer(minLength: 8)
                Text(fertileValue)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.16)))
        }
    }

    private var fertileValue: String {
        if snap.isFertileToday {
            let e = snap.fertileEndsIn ?? 0
            return e == 0 ? "Now · ends today" : "Now · ends in \(days(e))"
        }
        return "Starts in \(days(snap.fertileStartsIn ?? 0))"
    }

    private func phaseStrip(labels: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(Event.EventType.allCases) { p in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(settings.phaseColor(for: p).opacity(p == snap.phase ? 1 : 0.25))
                        .frame(height: 6)
                        .widgetAccentable(p == snap.phase)
                    if labels {
                        Text(p.rawValue.capitalized)
                            .font(.caption2.weight(p == snap.phase ? .semibold : .regular))
                            .foregroundColor(p == snap.phase ? DS.Color.primaryText : DS.Color.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statsRow: some View {
        let items: [(String, String)] = [
            snap.cycleStartDate.map { ("CYCLE START", $0.formatted(.dateTime.month(.abbreviated).day())) },
            snap.averageCycleLength.map { ("AVG CYCLE", days($0)) },
            snap.averagePeriodLength.map { ("AVG PERIOD", days($0)) }
        ].compactMap { $0 }
        if !items.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle().fill(DS.Color.separator).frame(width: 1, height: 28)
                    }
                    VStack(spacing: 3) {
                        Text(item.0)
                            .font(.caption2.weight(.semibold))
                            .tracking(0.6)
                            .foregroundColor(DS.Color.secondaryText)
                        Text(item.1)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(DS.Color.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func progressBar(day: Int, length: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Day \(day) of \(length)")
                .font(.caption.weight(.medium))
                .foregroundColor(DS.Color.secondaryText)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.18))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(1, Double(day) / Double(length)))
                        .widgetAccentable()
                }
            }
            .frame(height: 8)
        }
        .accessibilityHidden(true)
    }

    private func tile(title: String, value: String, detail: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundColor(DS.Color.secondaryText)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(DS.Color.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Color.cardBackground))
    }

    // MARK: - Sizes

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                moon
                Spacer(minLength: 4)
                fertileChip.padding(.top, 6)
            }
            Spacer(minLength: 0)
            header
            smallPeriodLine.padding(.top, 6)
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
                        Text(d == 0 ? "Expected today" : "In \(days(d))")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundColor(periodColor)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                    }
                    .padding(.top, 8)
                }
                Spacer(minLength: 0)
                mediumFertileLine
                phaseStrip(labels: false)
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                moon
                header
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                tile(title: "NEXT PERIOD",
                     value: snap.daysUntilNext.map { $0 == 0 ? "Today" : "In \(days($0))" } ?? "Unknown",
                     detail: snap.nextPeriodDate.map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) },
                     tint: periodColor)
                if let next = snap.nextPhase, let d = snap.daysUntilNextPhase {
                    tile(title: "NEXT PHASE",
                         value: "In \(days(d))",
                         detail: next.displayName,
                         tint: settings.phaseColor(for: next))
                }
            }
            fertileBanner
            statsRow
            Spacer(minLength: 0)
            if let day = snap.cycleDay, let length = snap.cycleLength, length > 0 {
                progressBar(day: day, length: length)
            }
            phaseStrip(labels: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - No cycle day

    /// Shown when no cycle day applies: due today, overdue, upcoming (from past cycles), or nothing logged.
    private var inactiveCopy: (title: String, subtitle: String) {
        if let o = snap.overdueDays { return ("Period \(days(o)) late", "Open RhythmX to log.") }
        if let d = snap.daysUntilNext {
            return d == 0 ? ("Period expected today", "Open RhythmX to log.")
                          : ("Next period in \(days(d))", "Open RhythmX to log.")
        }
        return ("No active cycle", "Open RhythmX to start.")
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
