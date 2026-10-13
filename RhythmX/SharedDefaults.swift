//  SharedDefaults.swift

import Foundation
import WidgetKit

enum PersistenceKeys {
    static let events = "com.example.rhythm(x).events"
    static let archivedData = "com.example.rhythm(x).archivedData"
}

enum AppGroup {
    static let id = "group.beta.Rhythm"
    static let migrationFlag = "appGroupMigrationV1"

    /// Shared store. Falls back to `.standard` when the App Group is not provisioned, so the app keeps
    /// reading and writing one consistent store instead of silently forking into a private suite.
    static let defaults: UserDefaults = {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil,
              let suite = UserDefaults(suiteName: id) else { return .standard }
        return suite
    }()

    private static let migratedKeys: [String] = [
        PersistenceKeys.events, PersistenceKeys.archivedData,
        "phaseColor1", "phaseColor2", "phaseColor3", "phaseColor4"
    ]

    /// Copies legacy values into the group once. Never deletes legacy keys, never overwrites group values.
    static func migrateIfNeeded(from legacy: UserDefaults = .standard, to group: UserDefaults = AppGroup.defaults) {
        guard legacy !== group, !group.bool(forKey: migrationFlag) else { return }
        var copiedAny = false
        for key in migratedKeys {
            if group.object(forKey: key) == nil, let value = legacy.object(forKey: key) {
                group.set(value, forKey: key)
                copiedAny = true
            }
        }
        // Only lock after a real copy, so an empty legacy read at launch can be retried next launch.
        if copiedAny {
            group.set(true, forKey: migrationFlag)
            reloadWidgets()   // a widget added before this first launch was empty; refill it now
        }
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
