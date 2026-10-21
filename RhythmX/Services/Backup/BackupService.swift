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

    /// Added to the restore message when the file turned Daily insights on but iOS does not allow notifications.
    static let dailyInsightsOffNote = "Daily insights was on in the file, but notifications are off for RhythmX, so it is off for now. You can allow notifications in iPhone Settings and turn it on in Notifications."

    /// After a restore: Daily insights on without notification permission could never fire, so it is turned
    /// back off. Returns true when it was turned off. Nothing is asked while the switch is off.
    static func checkDailyInsightsAccess(settings: AppSettings, isAuthorized: () async -> Bool) async -> Bool {
        guard settings.dailyInsightsOn else { return false }
        guard await isAuthorized() else {
            settings.dailyInsightsOn = false
            return true
        }
        return false
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
            // Phase colors are fixed since 2.0. The field stays in the format so older readers still open the
            // file; it always carries the fixed defaults.
            phaseColors: AppSettings.phaseColorHexes,
            notificationsEnabled: notificationsEnabled,
            notifyDayBefore: notifyDayBefore,
            notifyDayOf: notifyDayOf,
            fertileStartOn: fertileStartOn,
            fertileOvulationOn: fertileOvulationOn,
            trackingMode: trackingMode.rawValue,
            defaultModeOnLaunch: defaultModeOnLaunch,
            themeID: themeID,
            weeklyCheckIn: weeklyCheckIn,
            dailyInsightsOn: dailyInsightsOn,
            dailyInsightsHour: dailyInsightsHour,
            dailyInsightsMinute: dailyInsightsMinute,
            dailyInsightsDiscreet: dailyInsightsDiscreet
        )
    }

    /// Overwrites the settings AppSettings currently stores. Used only by Replace.
    func apply(_ settings: BackupSettings) {
        // `phaseColors` is ignored: phase colors are fixed, and custom colors in 1.9.x files are not restored.
        notificationsEnabled = settings.notificationsEnabled
        notifyDayBefore = settings.notifyDayBefore
        notifyDayOf = settings.notifyDayOf
        fertileStartOn = settings.fertileStartOn
        fertileOvulationOn = settings.fertileOvulationOn
        if let mode = TrackingMode(rawValue: settings.trackingMode) { trackingMode = mode }
        if settings.defaultModeOnLaunch == "last" || TrackingMode(rawValue: settings.defaultModeOnLaunch) != nil {
            defaultModeOnLaunch = settings.defaultModeOnLaunch
        }
        weeklyCheckIn = settings.weeklyCheckIn
        // Tag reminders and the daily check-in in older files are never restored (Daily insights replaced
        // them). A file without Daily insights says nothing about it, so the device's setting stays.
        if let on = settings.dailyInsightsOn { dailyInsightsOn = on }
        if let hour = settings.dailyInsightsHour, (0...23).contains(hour) { dailyInsightsHour = hour }
        if let minute = settings.dailyInsightsMinute, (0...59).contains(minute) { dailyInsightsMinute = minute }
        if let discreet = settings.dailyInsightsDiscreet { dailyInsightsDiscreet = discreet }
        // Only a known theme id is applied; files from before themes say "default" and leave the theme alone.
        // A Plus theme is stored as it is: `DS.Theme.current` still shows Blush while Plus is off.
        if AppTheme.all.contains(where: { $0.id == settings.themeID }) { themeID = settings.themeID }
    }
}
