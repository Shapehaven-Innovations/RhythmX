//  LogTagIntent.swift
//
//  Quick Log: the interactive widget's chips run this App Intent, which appends one tag to today's event in
//  the shared store. Compiled into the app and the widget extension. Every write goes through the pure
//  `QuickLogWriter`, which applies the same rules as `EventStore.logTag` (Task 7): one-per-day tags are never
//  doubled, repeatable tags ("Hot Flashes") count each time, and only Menopause creates a carrier event.
//  The mode comes from the shared store, never from the intent: a widget still showing the previous mode's
//  chips (its timeline has not reloaded yet) writes nothing.

import AppIntents
import Foundation

// MARK: - Chips

struct QuickLogChip: Equatable, Identifiable {
    let category: TagCategory
    let value: String
    /// Chip text; the stored tag is always `raw`.
    let label: String

    init(_ category: TagCategory, _ value: String, label: String? = nil) {
        self.category = category
        self.value = value
        self.label = label ?? value
    }

    var raw: String { "\(category.rawValue):\(value)" }
    var id: String { raw }
}

enum QuickLogChips {
    /// Four chips per mode, in display order.
    static func chips(for mode: TrackingMode) -> [QuickLogChip] {
        switch mode {
        case .cycle:
            return [QuickLogChip(.symptom, "Cramps"), QuickLogChip(.mood, "Tired"),
                    QuickLogChip(.mood, "Happy"), QuickLogChip(.symptom, "Flow")]
        case .planning:
            return [QuickLogChip(.cervicalMucus, "Egg White"), QuickLogChip(.planning, "Ovulation Test Positive"),
                    QuickLogChip(.planning, "Intercourse"), QuickLogChip(.basalTemp, "Elevated BBT", label: "Basal Temp")]
        case .menopause:
            return [QuickLogChip(.menopause, "Hot Flashes"), QuickLogChip(.menopause, "Night Sweats"),
                    QuickLogChip(.menopause, "Poor Sleep"), QuickLogChip(.mood, "Calm")]
        }
    }

    /// Whether a tap on a chip is honoured while `mode` is the stored tracking mode. The widget may still show
    /// the previous mode's chips until its timeline reloads, so a tag is written only when its category belongs
    /// to the stored mode and it is one of that mode's chips: a stale Hot Flashes chip in Cycle writes nothing,
    /// and a stale Symptom chip in Menopause creates no carrier.
    static func accepts(category: TagCategory, value: String, in mode: TrackingMode) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return TagLibrary.categories(for: mode).contains(category)
            && chips(for: mode).contains { $0.category == category && $0.value == value }
    }
}

// MARK: - Writer

enum QuickLogWriter {
    /// Appends "Category:Value" to the one event a tag logged on `date` attaches to in `mode`:
    /// Menopause uses that day's menopause event, or creates and appends a carrier (`.follicular`, mode
    /// `.menopause`, empty note); Cycle and Planning use a same-mode event first, then any other non-menopause
    /// event, and change nothing when the day has none. A one-per-day tag already on any event that day is
    /// refused; a repeatable tag is appended again. Returns whether `events` changed.
    @discardableResult
    static func append(category: TagCategory, value: String, to events: inout [Event], on date: Date, mode: TrackingMode) -> Bool {
        let raw = "\(category.rawValue):\(value.trimmingCharacters(in: .whitespacesAndNewlines))"
        let day = date.startOfDay
        if !TagLibrary.isRepeatable(category, value),
           events.contains(where: { $0.date.startOfDay == day && TagParser.split($0.tags).contains(raw) }) {
            return false
        }
        let sameDay = events.indices.filter { events[$0].date.startOfDay == day }
        let index: Int
        if mode == .menopause {
            if let existing = sameDay.first(where: { events[$0].effectiveMode == .menopause }) {
                index = existing
            } else {
                events.append(Event(eventType: .follicular, date: date, note: "", mode: .menopause))
                index = events.count - 1
            }
        } else if let own = sameDay.first(where: { events[$0].effectiveMode == mode }) {
            index = own
        } else if let other = sameDay.first(where: { events[$0].effectiveMode != .menopause }) {
            index = other
        } else {
            return false
        }
        events[index].tags = events[index].tags.isEmpty ? raw : events[index].tags + ", \(raw)"
        return true
    }

    /// The shared-store round trip the intent performs: decode, append in the stored tracking mode, encode.
    /// The mode is the one the app stored (`AppSettings.trackingMode`), and a chip that does not belong to it
    /// (`QuickLogChips.accepts`) is refused. Nothing is written when the tag is refused or the stored events
    /// cannot be read (never overwrite data that did not decode). Returns whether the store changed.
    @discardableResult
    static func log(category: TagCategory, value: String, defaults: UserDefaults = AppGroup.defaults, now: Date = Date()) -> Bool {
        let mode = defaults.string(forKey: "trackingMode").flatMap(TrackingMode.init(rawValue:)) ?? .cycle
        guard QuickLogChips.accepts(category: category, value: value, in: mode) else { return false }
        var events: [Event]
        if let data = defaults.data(forKey: PersistenceKeys.events) {
            guard let decoded = try? JSONDecoder().decode([Event].self, from: data) else { return false }
            events = decoded
        } else {
            events = []
        }
        guard append(category: category, value: value, to: &events, on: now, mode: mode),
              let data = try? JSONEncoder().encode(events) else { return false }
        defaults.set(data, forKey: PersistenceKeys.events)
        return true
    }
}

// MARK: - Intent

struct LogTagIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Tag"
    static let description = IntentDescription("Adds a tag to today in RhythmX.")
    static let isDiscoverable = false

    @Parameter(title: "Category") var category: String
    @Parameter(title: "Tag") var value: String

    init() {
        category = ""
        value = ""
    }

    init(category: String, value: String) {
        self.category = category
        self.value = value
    }

    var tagCategory: TagCategory? { TagCategory(rawValue: category) }

    func perform() async throws -> some IntentResult {
        guard let tagCategory, !value.isEmpty else { return .result() }
        let defaults = AppGroup.defaults
        // The chips are only shown while Plus is on (with the widget grace); the gate is checked here too.
        guard Entitlement.load(from: defaults).isPlus(now: Date()) else { return .result() }
        if QuickLogWriter.log(category: tagCategory, value: value, defaults: defaults, now: Date()) {
            AppGroup.reloadWidgets()
        }
        return .result()
    }
}
