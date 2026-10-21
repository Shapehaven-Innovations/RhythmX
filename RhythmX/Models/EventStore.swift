//
//  EventStore.swift
//

import Foundation
import SwiftUI

@MainActor
class EventStore: ObservableObject {
    @Published var events = [Event]()
    @Published var preview: Bool
    @Published var changedEvent: Event?
    @Published var movedEvent: Event?
    
    // Key for storing current events in UserDefaults
    private let eventsKey = PersistenceKeys.events

    // MARK: - NEW: For immediate calendar reload
    @Published var shouldReloadAll: Bool = false
    @Published var persistenceError: String? = nil

    init(preview: Bool = false) {
        self.preview = preview
        fetchEvents()
    }

    /// Load from UserDefaults (or provide empty if in preview)
    func fetchEvents() {
        if preview {
            events = []
        } else {
            loadFromUserDefaults()
        }
    }

    // MARK: - Mode filters
    /// Events that take part in cycle statistics, prediction, the fertile window, widgets and export.
    /// Legacy (nil mode) and Planning events count as cycle data; Menopause events never do.
    var cycleEvents: [Event] { events.filter { $0.effectiveMode != .menopause } }

    var menopauseEvents: [Event] { events.filter { $0.effectiveMode == .menopause } }

    // MARK: - CRUD
    func add(_ newEvent: Event) {
        events.append(newEvent)
        changedEvent = newEvent
        saveToUserDefaults()
    }

    func delete(_ event: Event) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            changedEvent = events.remove(at: idx)
            saveToUserDefaults()
        }
    }

    /// Replaces the event with the same id. Levels for tags no longer in `tags` are dropped.
    func update(_ event: Event) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            var event = event
            event.pruneIntensities()
            movedEvent = events[idx]
            events[idx] = event
            changedEvent = event
            saveToUserDefaults()
        }
    }

    // MARK: - Generate cycle events
    /// Replaces the cycle events with a freshly generated cycle. Menopause entries are kept: they belong
    /// to no cycle, and the Menopause archive prompt promises that the last week stays.
    func generateCycleEvents(startDate: Date, cycleLength: Int = 28) {
        events = menopauseEvents + CycleGenerator.events(startDate: startDate, cycleLength: cycleLength)
        // Save after generation
        saveToUserDefaults()
        // IMPORTANT: Do NOT flip `shouldReloadAll` here yet.
        // We want it to reload only after user taps "OK" in the alert.
    }

    // Optional: fetch historical events
    func fetchHistoricalEvents(for range: TimeInterval) -> [Event] {
        let startDate = Date().addingTimeInterval(-range)
        return events.filter { $0.date >= startDate }
    }

    // MARK: - Clear All Events
    /// Public helper that removes all events and immediately saves to UserDefaults.
    func clearAllEvents() {
        events.removeAll()
        saveToUserDefaults()
        // Also do NOT flip `shouldReloadAll` here; wait for "OK" in the alert.
    }

    // MARK: - Restore
    /// Replaces every event in one assignment, then saves once.
    func replaceAll(_ newEvents: [Event]) {
        events = newEvents
        saveToUserDefaults()
    }

    struct MergeCounts: Equatable {
        /// Events that were not on the phone and were appended.
        var added: Int
        /// Events already on the phone (same id, or same day, type and mode) whose tags gained what the file had,
        /// or whose tag intensity rose to the file's higher level.
        var updated: Int
    }

    /// Adds incoming events that are new. An incoming event whose id already exists, or that falls on the same
    /// start-of-day with the same `eventType` and effective mode as an event already present, is not added;
    /// instead its tags are merged into that event (`unionTags`), so a restore never drops a tag that was
    /// logged on only one side. Tag intensities are merged too, keeping the higher level for a tag on both
    /// sides. The phone's event otherwise stays as it is (date, note, id).
    @discardableResult
    func merge(_ incoming: [Event]) -> MergeCounts {
        let calendar = Calendar.current
        func key(_ event: Event) -> DayType {
            DayType(day: calendar.startOfDay(for: event.date), type: event.eventType, mode: event.effectiveMode)
        }
        var merged = events
        var indexByID: [String: Int] = [:]
        var indexByDayType: [DayType: Int] = [:]
        for (index, event) in merged.enumerated() {
            indexByID[event.id] = index
            if indexByDayType[key(event)] == nil { indexByDayType[key(event)] = index }
        }
        var added = 0
        var updatedIndices = Set<Int>()
        for event in incoming {
            if let index = indexByID[event.id] ?? indexByDayType[key(event)] {
                if let unioned = Self.unionTags(merged[index].tags, adding: event.tags) {
                    merged[index].tags = unioned
                    updatedIndices.insert(index)
                }
                if Self.mergeIntensity(into: &merged[index], from: event) {
                    updatedIndices.insert(index)
                }
                continue
            }
            indexByID[event.id] = merged.count
            indexByDayType[key(event)] = merged.count
            merged.append(event)
            added += 1
        }
        let counts = MergeCounts(added: added, updated: updatedIndices.count)
        guard added > 0 || !updatedIndices.isEmpty else { return counts }
        events = merged
        saveToUserDefaults()
        return counts
    }

    /// `existing` plus whatever `incoming` has that it lacks, in the stored "a, b, c" form; nil when nothing is
    /// missing. A one-per-day tag is never doubled. A repeatable tag ("Hot Flashes") keeps the higher of the two
    /// counts (multiset union), so merging the same file twice does not inflate it.
    nonisolated static func unionTags(_ existing: String, adding incoming: String) -> String? {
        var result = TagParser.split(existing)
        let before = result.count
        var have: [String: Int] = [:]
        for raw in result { have[raw, default: 0] += 1 }
        var seen: [String: Int] = [:]
        for raw in TagParser.split(incoming) {
            seen[raw, default: 0] += 1
            let wanted = TagLibrary.isRepeatable(raw: raw) ? seen[raw, default: 0] : 1
            if have[raw, default: 0] < wanted {
                result.append(raw)
                have[raw, default: 0] += 1
            }
        }
        return result.count > before ? result.joined(separator: ", ") : nil
    }

    /// Adds `source`'s levels to `target` for tags `target` now holds, keeping the higher level.
    /// Returns whether a level changed.
    @discardableResult
    static func mergeIntensity(into target: inout Event, from source: Event) -> Bool {
        let present = Set(TagParser.split(target.tags))
        let incoming = source.tagIntensity?.filter { present.contains($0.key) }
        let merged = Event.mergedIntensity(target.tagIntensity, incoming)
        guard merged != target.tagIntensity else { return false }
        target.tagIntensity = merged
        return true
    }

    private struct DayType: Hashable {
        let day: Date
        let type: Event.EventType
        let mode: TrackingMode
    }

    // MARK: - Tags
    /// The one event a tag logged on `date` attaches to, always of the same kind as `mode`.
    /// Menopause uses that day's menopause event and, with none, creates and stores a carrier event,
    /// since it has no generated cycle days. Cycle and Planning share cycle events (one in the same
    /// mode first, then any other non-menopause event) and return nil when the day has none, as they
    /// always have. A menopause tag never lands on a cycle event; a cycle tag never lands on a carrier.
    @discardableResult
    func eventForLogging(on date: Date, mode: TrackingMode) -> Event? {
        let sameDay = events.filter { $0.date.startOfDay == date.startOfDay }
        if mode == .menopause {
            if let existing = sameDay.first(where: { $0.effectiveMode == .menopause }) { return existing }
            let carrier = Event(eventType: .follicular, date: date, note: "", mode: .menopause)
            add(carrier)
            return carrier
        }
        return sameDay.first(where: { $0.effectiveMode == mode })
            ?? sameDay.first(where: { $0.effectiveMode != .menopause })
    }

    /// True when `raw` is already on any event that day. Repeatable tags are never duplicates.
    func isDuplicateTag(_ raw: String, on date: Date) -> Bool {
        guard !TagLibrary.isRepeatable(raw: raw) else { return false }
        let target = date.startOfDay
        return events.contains { event in
            event.date.startOfDay == target && TagParser.split(event.tags).contains(raw)
        }
    }

    /// Appends `raw` to the one event `eventForLogging` picks, creating a Menopause carrier when needed,
    /// so a tag is counted once however many events share the day. `intensity` is stored beside the tag.
    /// A one-per-day tag already logged that day is a duplicate, except that logging it again at a different
    /// level (or with no level, which turns a stored level off) changes the stored level on the event that holds
    /// the tag instead. A repeatable tag is appended
    /// again and keeps the higher of its levels.
    /// Returns false, and changes nothing, when the tag is a duplicate or there is no event to hold it.
    @discardableResult
    func logTag(_ raw: String, on date: Date, mode: TrackingMode, intensity: TagIntensity? = nil) -> Bool {
        if isDuplicateTag(raw, on: date) {
            // Logging it again with no level turns a stored level off; the tag itself stays.
            guard var holder = events.first(where: {
                      $0.date.startOfDay == date.startOfDay && TagParser.split($0.tags).contains(raw)
                  }),
                  holder.intensity(for: raw) != intensity else { return false }
            holder.setIntensity(intensity, for: raw)
            update(holder)
            return true
        }
        // Re-read the picked event from `events`: creating a carrier saves, and that save may have folded in
        // tags the widget wrote meanwhile (`foldInExternalWrites`), which the returned copy would not carry.
        guard let picked = eventForLogging(on: date, mode: mode),
              var target = events.first(where: { $0.id == picked.id }) else { return false }
        target.tags = target.tags.isEmpty ? raw : target.tags + ", \(raw)"
        if let intensity {
            let level = max(intensity, target.intensity(for: raw) ?? intensity)
            target.setIntensity(level, for: raw)
        }
        update(target)
        return true
    }

    /// Clears `raw` from that day: every occurrence on every event of the day, with its level.
    /// Returns false, and changes nothing, when the day does not hold the tag.
    @discardableResult
    func clearTag(_ raw: String, on date: Date) -> Bool {
        let day = date.startOfDay
        let holders = events.filter { $0.date.startOfDay == day && TagParser.split($0.tags).contains(raw) }
        for var event in holders {
            event.tags = TagParser.removing(raw, from: event.tags)
            event.setIntensity(nil, for: raw)
            update(event)
        }
        return !holders.isEmpty
    }

    /// Remove one raw tag from every event in a phase.
    func removeTag(_ raw: String, in phase: Event.EventType) {
        for event in events where event.eventType == phase {
            guard TagParser.split(event.tags).contains(raw) else { continue }
            let newTags = TagParser.removing(raw, from: event.tags)
            if newTags != event.tags {
                var updated = event
                updated.tags = newTags
                update(updated)
            }
        }
    }

    // MARK: - Persistence
    /// The bytes last read from or written to the shared store, so `reloadFromDiskIfChanged` can tell a write
    /// made by another process (the Quick Log widget) from this store's own.
    private var lastSyncedData: Data?

    private func saveToUserDefaults() {
        foldInExternalWrites()
        do {
            let data = try JSONEncoder().encode(events)
            AppGroup.defaults.set(data, forKey: eventsKey)
            lastSyncedData = data
            AppGroup.reloadWidgets()
        } catch {
            print("Error encoding events: \(error)")
        }
    }

    /// Folds a write made by another process since this store last read or wrote the shared store (a tag
    /// logged from the Quick Log widget while the app was not active, with no scene activation in between)
    /// into memory before a save, so the save cannot overwrite it. Tags are unioned by event id (`unionTags`,
    /// so a one-per-day tag is never doubled). An event this store has never seen (a Menopause carrier the
    /// widget made) joins this store's event for the same day, type and mode, or is appended. An event this
    /// store deleted since its last sync stays deleted. Nothing happens when the bytes are unchanged or
    /// cannot be read.
    private func foldInExternalWrites() {
        guard !preview, let disk = AppGroup.defaults.data(forKey: eventsKey), disk != lastSyncedData,
              let external = try? JSONDecoder().decode([Event].self, from: disk) else { return }
        let synced = lastSyncedData.flatMap { try? JSONDecoder().decode([Event].self, from: $0) } ?? []
        let seenBefore = Set(synced.map(\.id))
        let calendar = Calendar.current
        func key(_ event: Event) -> DayType {
            DayType(day: calendar.startOfDay(for: event.date), type: event.eventType, mode: event.effectiveMode)
        }
        var merged = events
        var indexByID: [String: Int] = [:]
        var indexByDayType: [DayType: Int] = [:]
        for (index, event) in merged.enumerated() {
            indexByID[event.id] = index
            if indexByDayType[key(event)] == nil { indexByDayType[key(event)] = index }
        }
        var changed = false
        for event in external {
            let target: Int?
            if let index = indexByID[event.id] {
                target = index
            } else if seenBefore.contains(event.id) {
                continue   // this store deleted it since its last sync; the delete stands
            } else {
                target = indexByDayType[key(event)]
            }
            if let target {
                let before = Set(TagParser.split(merged[target].tags))
                if let unioned = Self.unionTags(merged[target].tags, adding: event.tags) {
                    merged[target].tags = unioned
                    changed = true
                }
                // Only levels for tags the external write added: a level this store changed since its last
                // sync is newer than the one on disk. (The widget never writes levels.)
                if let external = event.tagIntensity?.filter({ !before.contains($0.key) }), !external.isEmpty {
                    var copy = event
                    copy.tagIntensity = external
                    if Self.mergeIntensity(into: &merged[target], from: copy) { changed = true }
                }
            } else {
                indexByID[event.id] = merged.count
                indexByDayType[key(event)] = merged.count
                merged.append(event)
                changed = true
            }
        }
        if changed { events = merged }
    }

    private func loadFromUserDefaults() {
        guard let data = AppGroup.defaults.data(forKey: eventsKey) else {
            return
        }
        do {
            let decoded = try JSONDecoder().decode([Event].self, from: data)
            self.events = decoded
            lastSyncedData = data
        } catch {
            persistenceError = "Could not load your events. Your data may be corrupted."
        }
    }

    /// Picks up a change written to the shared store while the app was not in front (a tag logged from the
    /// Quick Log widget), so the next save does not overwrite it. Does nothing when the bytes are unchanged
    /// or cannot be read.
    func reloadFromDiskIfChanged() {
        guard !preview, let data = AppGroup.defaults.data(forKey: eventsKey), data != lastSyncedData,
              let decoded = try? JSONDecoder().decode([Event].self, from: data) else { return }
        events = decoded
        lastSyncedData = data
    }

    // MARK: - NEW: Force calendar to reload all icons
    func reloadCalendarIcons() {
        shouldReloadAll.toggle()
    }
}

