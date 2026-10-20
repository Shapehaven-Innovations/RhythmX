//
//  ArchivedDataStore.swift
//  RhythmX
//
//  Created by user on 1/31/25.
//
import Foundation
import UserNotifications

@MainActor
class ArchivedDataStore: ObservableObject {
    @Published var archivedBlocks: [ArchivedDataBlock] = []
    @Published var persistenceError: String? = nil

    // Adjust your UserDefaults key, if needed
    private let archivedDataKey = PersistenceKeys.archivedData

    init() {
        loadArchivedData()
    }

    func loadArchivedData() {
        guard let data = AppGroup.defaults.data(forKey: archivedDataKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([ArchivedDataBlock].self, from: data)
            self.archivedBlocks = decoded
        } catch {
            persistenceError = "Could not load your archived cycles. Your data may be corrupted."
        }
    }

    // MARK: - Mode filters
    /// Blocks archived under one mode; nil returns every block (the Past Cycles "All" filter).
    func blocks(matching filter: TrackingMode?) -> [ArchivedDataBlock] {
        guard let filter else { return archivedBlocks }
        return archivedBlocks.filter { $0.effectiveMode == filter }
    }

    /// Blocks that take part in cycle statistics and prediction: everything except Menopause.
    var cycleBlocks: [ArchivedDataBlock] { archivedBlocks.filter { $0.effectiveMode != .menopause } }

    /// The Past Cycles list: `blocks(matching:)` narrowed to the events whose tags contain `text`.
    /// Blank text returns the plain filter. A narrowed block keeps its id, date and mode.
    func blocks(matching filter: TrackingMode?, search text: String) -> [ArchivedDataBlock] {
        let candidates = blocks(matching: filter)
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return candidates }

        return candidates.compactMap { block in
            let filteredPhases = block.groupedEvents.compactMap { phase -> ArchivedDataBlock.PhaseEvents? in
                let matchingEvents = phase.events.filter {
                    $0.tags.range(of: query, options: .caseInsensitive) != nil
                }
                guard !matchingEvents.isEmpty else { return nil }
                return ArchivedDataBlock.PhaseEvents(eventType: phase.eventType, events: matchingEvents)
            }
            guard !filteredPhases.isEmpty else { return nil }
            return ArchivedDataBlock(id: block.id, date: block.date, groupedEvents: filteredPhases, mode: block.mode)
        }
    }

    // MARK: - Archive action
    /// Menopause entries younger than this stay live so the weekly view keeps the current week.
    static let menopauseArchiveAgeDays = 7

    /// The live events the Archive action moves in `mode`. Cycle and Planning move every cycle event
    /// (legacy, Cycle and Planning), as 1.9.1 did; menopause entries stay live and never enter a cycle
    /// block. Menopause moves only menopause events older than `menopauseArchiveAgeDays`.
    static func eventsToArchive(from events: [Event], mode: TrackingMode, today: Date = Date(),
                                calendar: Calendar = .current) -> [Event] {
        guard mode == .menopause else { return events.filter { $0.effectiveMode != .menopause } }
        let cutoff = calendar.date(byAdding: .day, value: -menopauseArchiveAgeDays, to: calendar.startOfDay(for: today))!
        return events
            .filter { $0.effectiveMode == .menopause && $0.date < cutoff }
            .sorted { $0.date < $1.date }
    }

    /// Appends one block holding `events`, archived under `mode`. Cycle blocks store no mode so
    /// they keep the 1.9.x shape. Cycle and Planning group by phase exactly as the Archive prompt
    /// always has; Menopause has no phases, so it is one group under `.follicular`.
    /// Events are stored as they are; the mode is recorded on the block only. Nil when `events` is empty.
    @discardableResult
    func archiveCurrent(events: [Event], mode: TrackingMode) -> ArchivedDataBlock? {
        guard !events.isEmpty else { return nil }

        let groupedPhases: [ArchivedDataBlock.PhaseEvents]
        if mode == .menopause {
            groupedPhases = [ArchivedDataBlock.PhaseEvents(eventType: .follicular, events: events)]
        } else {
            groupedPhases = Dictionary(grouping: events) { $0.eventType }
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { (key, events) in
                    ArchivedDataBlock.PhaseEvents(eventType: key, events: events)
                }
        }

        let newBlock = ArchivedDataBlock(
            id: UUID(),
            date: Date(),
            groupedEvents: groupedPhases,
            mode: mode == .cycle ? nil : mode
        )
        appendArchivedBlock(newBlock)
        return newBlock
    }

    /// The Archive action: moves `eventsToArchive` out of `eventStore` into a new block. Only the moved
    /// events leave the store; the other mode's entries stay live.
    /// Returns the block, or nil (and changes nothing) when there is nothing to move.
    @discardableResult
    func archiveCurrent(from eventStore: EventStore, mode: TrackingMode, today: Date = Date()) -> ArchivedDataBlock? {
        let moving = Self.eventsToArchive(from: eventStore.events, mode: mode, today: today)
        guard let block = archiveCurrent(events: moving, mode: mode) else { return nil }
        let movedIds = Set(moving.map(\.id))
        eventStore.replaceAll(eventStore.events.filter { !movedIds.contains($0.id) })
        return block
    }

    func saveArchivedData() {
        do {
            let data = try JSONEncoder().encode(archivedBlocks)
            AppGroup.defaults.set(data, forKey: archivedDataKey)
            AppGroup.reloadWidgets()
        } catch {
            print("Error encoding archived data: \(error)")
        }
    }

    func appendArchivedBlock(_ newBlock: ArchivedDataBlock) {
        archivedBlocks.append(newBlock)
        archivedBlocks.sort { $0.date > $1.date }
        saveArchivedData()

        // Trigger first-time notification prompt
        let hasPrompted = UserDefaults.standard.bool(forKey: "hasPromptedNotifications")
        if !hasPrompted {
            UserDefaults.standard.set(true, forKey: "hasPromptedNotifications")
            NotificationCenter.default.post(name: .rhythmxPromptNotifications, object: nil)
        }

        // Reschedule reminders if notifications are enabled
        let enabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        let dayBefore = UserDefaults.standard.bool(forKey: "notifyDayBefore")
        let dayOf = UserDefaults.standard.bool(forKey: "notifyDayOf")
        if enabled, let predicted = CyclePredictionService.predictedStartDate(from: cycleBlocks) {
            NotificationScheduler.scheduleCycleReminders(for: predicted, dayBefore: dayBefore, dayOf: dayOf)
        }
    }

    /// Replaces every archived block in one assignment (newest first), then saves once.
    func replaceAll(_ blocks: [ArchivedDataBlock]) {
        archivedBlocks = blocks.sorted { $0.date > $1.date }
        saveArchivedData()
    }

    /// Adds incoming blocks whose id is not already present, keeps newest-first order,
    /// saves once and returns the count added.
    @discardableResult
    func merge(_ incoming: [ArchivedDataBlock]) -> Int {
        var ids = Set(archivedBlocks.map(\.id))
        var merged = archivedBlocks
        for block in incoming where !ids.contains(block.id) {
            ids.insert(block.id)
            merged.append(block)
        }
        let added = merged.count - archivedBlocks.count
        guard added > 0 else { return 0 }
        archivedBlocks = merged.sorted { $0.date > $1.date }
        saveArchivedData()
        return added
    }

    /// Clear all archived data, then save.
    func clearAllArchivedData() {
        archivedBlocks.removeAll()
        saveArchivedData()
    }

    /// Remove one archived cycle by id, then save. Unknown ids are ignored.
    func deleteArchivedBlock(id: UUID) {
        guard archivedBlocks.contains(where: { $0.id == id }) else { return }
        archivedBlocks.removeAll { $0.id == id }
        saveArchivedData()
    }

    func updateArchivedEventTag(eventId: String, newTags: String) {
        for (blockIndex, block) in archivedBlocks.enumerated() {
            var didUpdate = false
            let updatedPhases = block.groupedEvents.map { phase -> ArchivedDataBlock.PhaseEvents in
                let updatedEvents = phase.events.map { event -> Event in
                    if event.id == eventId {
                        didUpdate = true
                        var newEvent = event
                        newEvent.tags = newTags
                        return newEvent
                    }
                    return event
                }
                return ArchivedDataBlock.PhaseEvents(eventType: phase.eventType, events: updatedEvents)
            }
            if didUpdate {
                let updatedBlock = ArchivedDataBlock(id: block.id, date: block.date, groupedEvents: updatedPhases, mode: block.mode)
                archivedBlocks[blockIndex] = updatedBlock
                saveArchivedData()
                break
            }
        }
    }
}

extension Notification.Name {
    static let rhythmxPromptNotifications = Notification.Name("rhythmxPromptNotifications")
}
