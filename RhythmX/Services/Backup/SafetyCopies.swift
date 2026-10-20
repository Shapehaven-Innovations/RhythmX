//  SafetyCopies.swift
//
//  Copies of the user's data that RhythmX keeps on this phone on its own, as ordinary unencrypted
//  `.rhythmx` backup files in `Application Support/RhythmX/Backup`, so any of them can be restored
//  in-app through the normal restore flow:
//
//  - `pre-update-yyyy-MM-dd-HHmmss.rhythmx`: the data as it was before the 2.0 update, converted once
//    from the raw `LegacySnapshot` file. Never deleted automatically (spec): it stays until the user
//    taps Delete in Settings, however old it is and whether or not a backup has been made since.
//  - `pre-restore-yyyy-MM-dd-HHmmss.rhythmx`: the data as it was right before a Replace restore.
//    At most three are kept, and each expires after 30 days.
//
//  Every file is written with complete file protection and excluded from iCloud and device backup.
//  `prune` runs at launch and after every successful write.

import Foundation

struct SafetyCopy: Equatable, Identifiable {
    enum Kind: Equatable {
        case preUpdate
        case preRestore
    }

    let url: URL
    let date: Date
    let kind: Kind

    var id: URL { url }
}

enum SafetyCopies {
    static let preUpdatePrefix = "pre-update-"
    static let preRestorePrefix = "pre-restore-"
    static let maxPreRestoreCopies = 3
    static let preRestoreLifetime: TimeInterval = 30 * 86_400
    /// Set in the App Group defaults once the raw pre-update snapshot has been converted.
    static let convertedFlagKey = "legacySnapshotV2Converted"

    enum SafetyCopyError: Error, Equatable {
        case noDirectory
        case notASafetyCopy
        case unreadableLegacySnapshot
    }

    static var defaultDirectory: URL? { LegacySnapshot.defaultDirectory }

    // MARK: Names

    private static let stampLength = "yyyy-MM-dd-HHmmss".count

    private static func stampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }

    private static func prefix(for kind: SafetyCopy.Kind) -> String {
        switch kind {
        case .preUpdate: return preUpdatePrefix
        case .preRestore: return preRestorePrefix
        }
    }

    /// `<prefix>yyyy-MM-dd-HHmmss.rhythmx`, in local time.
    static func fileName(kind: SafetyCopy.Kind, date: Date) -> String {
        "\(prefix(for: kind))\(stampFormatter().string(from: date)).\(BackupFile.fileExtension)"
    }

    /// Kind and date from a file name, or nil when the name is not a safety copy's.
    /// A copy written in the same second as another carries a `-2`, `-3`... suffix after the stamp.
    private static func parse(_ name: String, formatter: DateFormatter) -> (kind: SafetyCopy.Kind, date: Date, suffix: Int)? {
        let ext = ".\(BackupFile.fileExtension)"
        guard name.hasSuffix(ext) else { return nil }
        let kind: SafetyCopy.Kind
        let rest: Substring
        if name.hasPrefix(preRestorePrefix) {
            kind = .preRestore
            rest = name.dropFirst(preRestorePrefix.count).dropLast(ext.count)
        } else if name.hasPrefix(preUpdatePrefix) {
            kind = .preUpdate
            rest = name.dropFirst(preUpdatePrefix.count).dropLast(ext.count)
        } else {
            return nil
        }
        guard rest.count >= stampLength,
              let date = formatter.date(from: String(rest.prefix(stampLength))) else { return nil }
        let tail = rest.dropFirst(stampLength)
        if tail.isEmpty { return (kind, date, 1) }
        guard tail.first == "-", let suffix = Int(tail.dropFirst()) else { return nil }
        return (kind, date, suffix)
    }

    // MARK: List

    /// Every safety copy in `directory`, newest first.
    static func list(directory: URL? = SafetyCopies.defaultDirectory) -> [SafetyCopy] {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let formatter = stampFormatter()
        return names
            .compactMap { name -> (SafetyCopy, Int)? in
                guard let parsed = parse(name, formatter: formatter) else { return nil }
                let url = directory.appendingPathComponent(name, isDirectory: false)
                return (SafetyCopy(url: url, date: parsed.date, kind: parsed.kind), parsed.suffix)
            }
            .sorted { lhs, rhs in
                lhs.0.date != rhs.0.date ? lhs.0.date > rhs.0.date : lhs.1 > rhs.1
            }
            .map(\.0)
    }

    // MARK: Write

    /// Writes `data` (a backup file) as a safety copy, then prunes. Throws when the directory is missing
    /// or any step of the write fails; a file that could not be excluded from device backup is removed
    /// again. Pruning runs only after the write succeeded and never removes a URL in `protecting`.
    @discardableResult
    static func write(_ data: Data,
                      kind: SafetyCopy.Kind,
                      date: Date = Date(),
                      now: Date = Date(),
                      directory: URL? = SafetyCopies.defaultDirectory,
                      protecting: Set<URL> = []) throws -> URL {
        let url = try writeFile(data, kind: kind, date: date, directory: directory)
        prune(now: now, directory: directory, protecting: protecting.union([url]))
        return url
    }

    private static func writeFile(_ data: Data, kind: SafetyCopy.Kind, date: Date, directory: URL?) throws -> URL {
        guard let directory else { throw SafetyCopyError.noDirectory }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var url = directory.appendingPathComponent(fileName(kind: kind, date: date), isDirectory: false)
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let base = "\(prefix(for: kind))\(stampFormatter().string(from: date))-\(suffix)"
            url = directory.appendingPathComponent("\(base).\(BackupFile.fileExtension)", isDirectory: false)
            suffix += 1
        }

        try data.write(to: url, options: [.atomic, .completeFileProtection])
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return url
    }

    // MARK: Delete

    /// Removes one safety copy. Throws for a URL that is not a safety copy in `directory`
    /// (including one that is already gone) and for any file system error.
    static func delete(_ url: URL, directory: URL? = SafetyCopies.defaultDirectory) throws {
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        guard list(directory: directory).contains(where: {
            $0.url.standardizedFileURL.resolvingSymlinksInPath() == target
        }) else {
            throw SafetyCopyError.notASafetyCopy
        }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: Prune

    /// Applies the retention rules. Best effort: a file that cannot be removed stays until the next prune.
    /// - Pre-restore copies: the newest three are kept; any older than 30 days is removed.
    /// - Pre-update copies are never removed here. Only `delete`, from the user's Delete button, removes one.
    /// A URL in `protecting` (a copy that is being restored) is never removed.
    static func prune(now: Date = Date(),
                      directory: URL? = SafetyCopies.defaultDirectory,
                      protecting: Set<URL> = []) {
        let protected = Set(protecting.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        var preRestoreSeen = 0
        for copy in list(directory: directory) {
            let expired: Bool
            switch copy.kind {
            case .preRestore:
                preRestoreSeen += 1
                expired = preRestoreSeen > maxPreRestoreCopies || now.timeIntervalSince(copy.date) > preRestoreLifetime
            case .preUpdate:
                expired = false
            }
            guard expired,
                  !protected.contains(copy.url.standardizedFileURL.resolvingSymlinksInPath().path) else { continue }
            try? FileManager.default.removeItem(at: copy.url)
        }
    }

    // MARK: Pre-update conversion

    /// Converts the raw pre-update snapshot (`LegacySnapshot`) into a `pre-update` safety copy, once.
    /// The raw blobs are decoded the way the stores decode them; a blob that fails to decode stops the
    /// conversion, leaves the raw file untouched and leaves the flag clear, so the next launch retries
    /// and nothing is lost. On success the flag is set, the raw file is removed (the `.rhythmx` copy
    /// exists by then), and the copies are pruned with the new copy explicitly protected (pre-update copies
    /// are never pruned anyway). Returns the new copy's URL, or nil when nothing was done.
    @discardableResult
    static func convertLegacySnapshotIfNeeded(defaults: UserDefaults = AppGroup.defaults,
                                              directory: URL? = SafetyCopies.defaultDirectory,
                                              flagKey: String = SafetyCopies.convertedFlagKey,
                                              settings: BackupSettings,
                                              appVersion: String,
                                              now: Date = Date()) -> URL? {
        guard !defaults.bool(forKey: flagKey), let directory,
              LegacySnapshot.exists(directory: directory) else { return nil }
        do {
            let raw = try LegacySnapshot.read(directory: directory)
            let decoder = JSONDecoder()
            let events = try raw.events.map { try decoder.decode([Event].self, from: $0) } ?? []
            let blocks = try raw.archivedData.map { try decoder.decode([ArchivedDataBlock].self, from: $0) } ?? []
            let payload = BackupPayload(events: events, archivedBlocks: blocks, settings: settings)
            let data = try BackupFile.make(payload, appVersion: appVersion, passphrase: nil, now: raw.createdAt)
            let url = try writeFile(data, kind: .preUpdate, date: raw.createdAt, directory: directory)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            defaults.set(true, forKey: flagKey)
            try? LegacySnapshot.delete(directory: directory)
            prune(now: now, directory: directory, protecting: [url])
            return url
        } catch {
            return nil
        }
    }
}
