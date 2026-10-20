//  LegacySnapshot.swift
//
//  Pre-migration safety net for the 1.9.x to 2.0 update. On the first 2.0 launch, before any store
//  loads or any migration runs, the raw `Data` stored under the events and archive keys is copied
//  byte-for-byte into Application Support. Once the stores can decode it, `SafetyCopies` converts it
//  into a restorable `pre-update` `.rhythmx` copy and only then removes this raw file.

import Foundation

enum LegacySnapshot {
    static let fileName = "legacy-snapshot-v2.json"
    static let defaultFlagKey = "legacySnapshotV2"

    /// `Application Support/RhythmX/Backup`. Files written here are excluded from iCloud and iTunes backup.
    /// Nil when Application Support is unavailable; there is no temporary-directory fallback, because
    /// the system may purge it and a snapshot there would set the flag and never be retried.
    static var defaultDirectory: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: false) else { return nil }
        return base.appendingPathComponent("RhythmX", isDirectory: true)
            .appendingPathComponent("Backup", isDirectory: true)
    }

    struct Payload: Codable {
        var events: Data?
        var archivedData: Data?
        var createdAt: Date
    }

    /// Reads the raw snapshot written by `writeIfNeeded`. Throws when it is missing or unreadable.
    static func read(directory: URL) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        return try decoder.decode(Payload.self, from: Data(contentsOf: fileURL(in: directory)))
    }

    /// Writes the snapshot once. Returns the file URL when a file was written, nil when nothing was done:
    /// already written (flag set), no directory, nothing to copy, or a write failure.
    ///
    /// No directory and a write failure leave the flag clear, so the next launch retries. Nothing under
    /// either key in either store is a fresh 2.0 install: there is no 1.9.x data to protect, and whatever
    /// is logged from now on is 2.0 data, so the flag is set and no later launch snapshots that data as a
    /// copy "from before the update".
    ///
    /// Each key is read from `defaults` (the App Group) and, when that has nothing, from `legacy`
    /// (the pre-App-Group store), the same source `AppGroup.migrateIfNeeded` copies from.
    @discardableResult
    static func writeIfNeeded(defaults: UserDefaults = AppGroup.defaults,
                              legacy: UserDefaults = .standard,
                              directory: URL? = LegacySnapshot.defaultDirectory,
                              flagKey: String = LegacySnapshot.defaultFlagKey) -> URL? {
        guard !defaults.bool(forKey: flagKey), let directory else { return nil }

        // A file with no flag (defaults reset, reinstall over an old container) is the older copy; keep it.
        if exists(directory: directory) {
            defaults.set(true, forKey: flagKey)
            return nil
        }

        let events = defaults.data(forKey: PersistenceKeys.events) ?? legacy.data(forKey: PersistenceKeys.events)
        let archived = defaults.data(forKey: PersistenceKeys.archivedData)
            ?? legacy.data(forKey: PersistenceKeys.archivedData)
        guard events != nil || archived != nil else {
            defaults.set(true, forKey: flagKey)
            return nil
        }

        let payload = Payload(events: events, archivedData: archived, createdAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        encoder.outputFormatting = [.sortedKeys]

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var url = fileURL(in: directory)
            try encoder.encode(payload).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            defaults.set(true, forKey: flagKey)
            return url
        } catch {
            return nil
        }
    }

    static func exists(directory: URL? = LegacySnapshot.defaultDirectory) -> Bool {
        guard let directory else { return false }
        return FileManager.default.fileExists(atPath: fileURL(in: directory).path)
    }

    /// Removes the snapshot file. Missing file is not an error.
    static func delete(directory: URL? = LegacySnapshot.defaultDirectory) throws {
        guard let directory else { return }
        let url = fileURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }
}
