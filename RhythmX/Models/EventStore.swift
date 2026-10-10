//
//  EventStore.swift
//

import Foundation
import SwiftUI

enum PersistenceKeys {
    static let events = "com.example.rhythm(x).events"
    static let archivedData = "com.example.rhythm(x).archivedData"
}

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

    func update(_ event: Event) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            movedEvent = events[idx]
            events[idx] = event
            changedEvent = event
            saveToUserDefaults()
        }
    }

    // MARK: - Generate cycle events
    func generateCycleEvents(startDate: Date, cycleLength: Int = 28) {
        events = CycleGenerator.events(startDate: startDate, cycleLength: cycleLength)
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

    // MARK: - Tags
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
    private func saveToUserDefaults() {
        do {
            let data = try JSONEncoder().encode(events)
            UserDefaults.standard.set(data, forKey: eventsKey)
        } catch {
            print("Error encoding events: \(error)")
        }
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: eventsKey) else {
            return
        }
        do {
            let decoded = try JSONDecoder().decode([Event].self, from: data)
            self.events = decoded
        } catch {
            persistenceError = "Could not load your events. Your data may be corrupted."
        }
    }

    // MARK: - NEW: Force calendar to reload all icons
    func reloadCalendarIcons() {
        shouldReloadAll.toggle()
    }
}

