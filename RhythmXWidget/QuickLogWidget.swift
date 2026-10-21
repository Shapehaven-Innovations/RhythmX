//  QuickLogWidget.swift
//
//  Small Plus widget: four tappable chips for the current tracking mode that save a tag to today without
//  opening the app (App Intents). Locked without Plus, like the Week Strip.

import SwiftUI
import WidgetKit

struct QuickLogEntry: TimelineEntry {
    let date: Date
    let state: PlusWidgetState
    let mode: TrackingMode
    let chips: [QuickLogChip]
    /// How many times each chip's tag is already on today's events, by `raw`.
    let counts: [String: Int]

    static func sample(date: Date = Date()) -> QuickLogEntry {
        QuickLogEntry(date: date, state: .unlocked, mode: .cycle, chips: QuickLogChips.chips(for: .cycle),
                      counts: ["Symptom:Cramps": 1])
    }
}

struct QuickLogTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry { .sample() }

    func getSnapshot(in context: Context, completion: @escaping (QuickLogEntry) -> Void) {
        completion(context.isPreview ? .sample() : Self.entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogEntry>) -> Void) {
        let now = Date()
        let midnight = now.startOfDay.diff(numDays: 1)
        // Now and midnight (the counts reset with the day), plus the entry at expiry plus grace that flips the
        // widget to the upgrade prompt without waiting for a reload.
        let slots = PlusWidgetState.timeline(base: [now, midnight], now: now, horizon: midnight,
                                             entitlement: Entitlement.load(from: AppGroup.defaults))
        completion(Timeline(entries: slots.map { Self.entry(at: $0.date) }, policy: .after(midnight)))
    }

    /// The chips follow the stored mode. The app reloads the timelines whenever the mode changes, and a tap on
    /// a chip that no longer matches the stored mode writes nothing (`QuickLogChips.accepts`).
    static func entry(at date: Date, defaults: UserDefaults = AppGroup.defaults) -> QuickLogEntry {
        let mode = defaults.string(forKey: "trackingMode").flatMap(TrackingMode.init(rawValue:)) ?? .cycle
        let chips = QuickLogChips.chips(for: mode)
        let state = PlusWidgetState.make(entitlement: Entitlement.load(from: defaults), now: date)
        guard state == .unlocked else {
            return QuickLogEntry(date: date, state: .locked, mode: mode, chips: chips, counts: [:])
        }
        let today = date.startOfDay
        let tags = PhaseWidgetSnapshot.loadEvents(from: defaults)
            .filter { $0.date.startOfDay == today }
            .flatMap { TagParser.split($0.tags) }
        var counts: [String: Int] = [:]
        for raw in tags { counts[raw, default: 0] += 1 }
        return QuickLogEntry(date: date, state: .unlocked, mode: mode, chips: chips,
                             counts: counts.filter { key, _ in chips.contains { $0.raw == key } })
    }
}

struct QuickLogWidget: Widget {
    let kind = "QuickLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickLogTimelineProvider()) { entry in
            QuickLogWidgetView(entry: entry)
                .containerBackground(DS.Color.pageBackground, for: .widget)
        }
        .configurationDisplayName("Quick Log")
        .description("Tap a tag to log it for today. RhythmX Plus.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - View

struct QuickLogWidgetView: View {
    let entry: QuickLogEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch entry.state {
        case .locked:
            PlusLockedWidgetView(detail: "Log a tag without opening the app.")
        case .unlocked:
            unlocked
        }
    }

    private var unlocked: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Quick Log")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DS.Color.primaryText)
                Spacer(minLength: 0)
                Text(entry.mode.title)
                    .font(.caption2)
                    .foregroundColor(DS.Color.secondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Quick Log, \(entry.mode.title) mode")
            Spacer(minLength: 0)
            let pairs = Array(entry.chips.prefix(4))
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(pairs.prefix(2)) { chip(for: $0) }
                }
                HStack(spacing: 6) {
                    ForEach(pairs.dropFirst(2)) { chip(for: $0) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func chip(for chip: QuickLogChip) -> some View {
        let count = entry.counts[chip.raw] ?? 0
        let logged = count > 0
        return Button(intent: LogTagIntent(category: chip.category.rawValue, value: chip.value)) {
            HStack(spacing: 3) {
                Text(chip.label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.7)
                if logged {
                    Text(count > 1 ? "\(count)" : "")
                        .font(.caption2.weight(.bold))
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundColor(logged ? DS.Color.onAccent : DS.Color.accent)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(logged ? DS.Color.accent : DS.Color.accent.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(chip.label)")
        .accessibilityValue(logged ? (count == 1 ? "Logged today" : "Logged \(count) times today") : "")
        .accessibilityHint(TagLibrary.isRepeatable(chip.category, chip.value) || !logged
                           ? "Adds \(chip.label) to today" : "Already logged today")
    }
}
