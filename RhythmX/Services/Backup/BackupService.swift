//
//  BackupService.swift
//
//  Collects a `BackupPayload` from the live stores and restores one by Merge or Replace.
//  Merge adds new events/cycles, merges the file's tags into same-day events already on the phone,
//  and never touches settings; Replace overwrites events, archived cycles and settings. Purchases are
//  never read or written here.
//

import Foundation

enum RestoreMode {
    case merge
    case replace
}

struct RestoreResult: Equatable {
    let eventsAdded: Int
    let blocksAdded: Int
    /// Merge only: events already on the phone whose tags gained what the file had. Replace reports 0.
    var eventsUpdated: Int = 0
}

struct BackupPreview: Equatable {
    let cycleCount: Int
    let eventCount: Int
    let earliest: Date?
    let latest: Date?
}

@MainActor
enum BackupService {
    static func makePayload(events: EventStore, archived: ArchivedDataStore, settings: AppSettings) -> BackupPayload {
        BackupPayload(
            events: events.events,
            archivedBlocks: archived.archivedBlocks,
            settings: settings.settingsSnapshot()
        )
    }

    /// Callers open and validate the file first (`BackupFile.open`), so a bad file never reaches the stores.
    @discardableResult
    static func restore(
        _ payload: BackupPayload,
        mode: RestoreMode,
        events: EventStore,
        archived: ArchivedDataStore,
        settings: AppSettings
    ) -> RestoreResult {
        switch mode {
        case .merge:
            let counts = events.merge(payload.events)
            let blocksAdded = archived.merge(payload.archivedBlocks)
            return RestoreResult(eventsAdded: counts.added, blocksAdded: blocksAdded, eventsUpdated: counts.updated)
        case .replace:
            // Everything is built before any store changes, then each store is assigned and saved once.
            let newEvents = payload.events
            let newBlocks = payload.archivedBlocks
            let newSettings = payload.settings
            events.replaceAll(newEvents)
            archived.replaceAll(newBlocks)
            settings.apply(newSettings)
            return RestoreResult(eventsAdded: newEvents.count, blocksAdded: newBlocks.count)
        }
    }

    /// Counts and date range shown before the user picks Merge or Replace.
    /// The range covers current events and the events inside archived cycles.
    static func preview(_ payload: BackupPayload) -> BackupPreview {
        let archivedEvents = payload.archivedBlocks.flatMap { $0.groupedEvents.flatMap(\.events) }
        let dates = (payload.events + archivedEvents).map(\.date)
        return BackupPreview(
            cycleCount: payload.archivedBlocks.count,
            eventCount: payload.events.count,
            earliest: dates.min(),
            latest: dates.max()
        )
    }
}

// Kept here rather than in AppSettings.swift: AppSettings.swift is also compiled by the widget
// target, which does not (and should not) include the backup types.
extension AppSettings {
    /// The settings that go into a backup. Purchases are not settings and are never included.
    func settingsSnapshot() -> BackupSettings {
        BackupSettings(
            phaseColors: [phaseColor1, phaseColor2, phaseColor3, phaseColor4],
            notificationsEnabled: notificationsEnabled,
            notifyDayBefore: notifyDayBefore,
            notifyDayOf: notifyDayOf,
            fertileStartOn: fertileStartOn,
            fertileOvulationOn: fertileOvulationOn,
            trackingMode: trackingMode.rawValue,
            defaultModeOnLaunch: defaultModeOnLaunch,
            // themeID is not stored by AppSettings yet; the themes task wires it. Until then it
            // round-trips as a harmless default and is ignored by `apply(_:)`.
            themeID: "default",
            reminders: ReminderStore.load(),
            dailyCheckIn: dailyCheckIn,
            weeklyCheckIn: weeklyCheckIn
        )
    }

    /// Overwrites the settings AppSettings currently stores. Used only by Replace.
    func apply(_ settings: BackupSettings) {
        let colors = settings.phaseColors
        if colors.count > 0 { phaseColor1 = colors[0] }
        if colors.count > 1 { phaseColor2 = colors[1] }
        if colors.count > 2 { phaseColor3 = colors[2] }
        if colors.count > 3 { phaseColor4 = colors[3] }
        notificationsEnabled = settings.notificationsEnabled
        notifyDayBefore = settings.notifyDayBefore
        notifyDayOf = settings.notifyDayOf
        fertileStartOn = settings.fertileStartOn
        fertileOvulationOn = settings.fertileOvulationOn
        if let mode = TrackingMode(rawValue: settings.trackingMode) { trackingMode = mode }
        if settings.defaultModeOnLaunch == "last" || TrackingMode(rawValue: settings.defaultModeOnLaunch) != nil {
            defaultModeOnLaunch = settings.defaultModeOnLaunch
        }
        // A file with no readable reminder list says nothing about reminders, so the stored list stays.
        if let reminders = settings.reminders { ReminderStore.save(reminders) }
        dailyCheckIn = settings.dailyCheckIn
        weeklyCheckIn = settings.weeklyCheckIn
        // themeID: no AppSettings property yet; the themes task applies it here.
    }
}
