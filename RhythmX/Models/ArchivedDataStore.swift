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
        if enabled, let predicted = CyclePredictionService.predictedStartDate(from: archivedBlocks) {
            NotificationScheduler.scheduleCycleReminders(for: predicted, dayBefore: dayBefore, dayOf: dayOf)
        }
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
                let updatedBlock = ArchivedDataBlock(id: block.id, date: block.date, groupedEvents: updatedPhases)
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
