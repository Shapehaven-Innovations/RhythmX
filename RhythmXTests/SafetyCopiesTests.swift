import XCTest
@testable import RhythmX

final class SafetyCopiesTests: XCTestCase {
    private let suiteName = "test.safetyCopies"
    private let legacySuiteName = "test.safetyCopies.standard"
    private let rawFlagKey = "test.safetyCopies.rawFlag"
    private let convertedFlagKey = "test.safetyCopies.converted"
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private let day: TimeInterval = 86_400

    private var defaults: UserDefaults!
    private var legacy: UserDefaults!
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
        UserDefaults(suiteName: legacySuiteName)!.removePersistentDomain(forName: legacySuiteName)
        legacy = UserDefaults(suiteName: legacySuiteName)!
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafetyCopiesTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
        UserDefaults(suiteName: legacySuiteName)!.removePersistentDomain(forName: legacySuiteName)
        try super.tearDownWithError()
    }

    // MARK: Helpers

    /// Places a copy on disk directly, without the prune that `write` runs.
    @discardableResult
    private func place(_ kind: SafetyCopy.Kind, daysAgo: Double, body: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = now.addingTimeInterval(-daysAgo * day)
        let url = directory.appendingPathComponent(SafetyCopies.fileName(kind: kind, date: date), isDirectory: false)
        try Data((body ?? "\(kind)-\(daysAgo)").utf8).write(to: url)
        return url
    }

    private func list() -> [SafetyCopy] {
        SafetyCopies.list(directory: directory)
    }

    private func ages(_ copies: [SafetyCopy]) -> [Double] {
        copies.map { (now.timeIntervalSince($0.date) / day).rounded() }
    }

    private func prune(protecting: Set<URL> = []) {
        SafetyCopies.prune(now: now, directory: directory, protecting: protecting)
    }

    private let settings = BackupSettings(
        phaseColors: ["#111111", "#222222", "#333333", "#444444"],
        notificationsEnabled: true, notifyDayBefore: true, notifyDayOf: false,
        fertileStartOn: false, fertileOvulationOn: false, trackingMode: "cycle",
        defaultModeOnLaunch: "last", themeID: "default", reminders: [], dailyCheckIn: nil, weeklyCheckIn: nil
    )

    private func convert() -> URL? {
        SafetyCopies.convertLegacySnapshotIfNeeded(
            defaults: defaults, directory: directory, flagKey: convertedFlagKey,
            settings: settings, appVersion: "2.0-test", now: now
        )
    }

    // MARK: List, write, delete

    func testListIsNewestFirstWithKinds() throws {
        try place(.preRestore, daysAgo: 5)
        try place(.preUpdate, daysAgo: 10)
        try place(.preRestore, daysAgo: 1)
        // Files that are not safety copies are ignored.
        try Data("raw".utf8).write(to: directory.appendingPathComponent(LegacySnapshot.fileName))
        try Data("x".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        try Data("x".utf8).write(to: directory.appendingPathComponent("pre-restore-garbage.rhythmx"))

        let copies = list()
        XCTAssertEqual(copies.map(\.kind), [.preRestore, .preRestore, .preUpdate])
        XCTAssertEqual(ages(copies), [1, 5, 10])
        XCTAssertEqual(copies.first?.date, now.addingTimeInterval(-day))
        XCTAssertTrue(SafetyCopies.list(directory: nil).isEmpty)
        XCTAssertTrue(SafetyCopies.list(directory: directory.appendingPathComponent("missing")).isEmpty)
    }

    func testWriteNamesProtectsAndExcludesFromBackup() throws {
        let url = try SafetyCopies.write(Data("copy".utf8), kind: .preRestore, date: now, now: now,
                                         directory: directory)
        XCTAssertEqual(url.lastPathComponent, SafetyCopies.fileName(kind: .preRestore, date: now))
        XCTAssertTrue(url.lastPathComponent.hasPrefix("pre-restore-"))
        XCTAssertEqual(url.pathExtension, "rhythmx")
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try Data(contentsOf: url), Data("copy".utf8))

        // A second copy in the same second gets its own file instead of overwriting the first.
        let second = try SafetyCopies.write(Data("second".utf8), kind: .preRestore, date: now, now: now,
                                            directory: directory)
        XCTAssertNotEqual(second, url)
        XCTAssertEqual(try Data(contentsOf: url), Data("copy".utf8))
        XCTAssertEqual(list().count, 2)
        XCTAssertEqual(list().first?.url.lastPathComponent, second.lastPathComponent, "the later write lists first")

        let update = try SafetyCopies.write(Data("u".utf8), kind: .preUpdate, date: now, now: now,
                                            directory: directory)
        XCTAssertTrue(update.lastPathComponent.hasPrefix("pre-update-"))
    }

    func testFileNameUsesSecondPrecisionTimestamp() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: now)
        XCTAssertEqual(SafetyCopies.fileName(kind: .preRestore, date: now), "pre-restore-\(stamp).rhythmx")
        XCTAssertEqual(SafetyCopies.fileName(kind: .preUpdate, date: now), "pre-update-\(stamp).rhythmx")
    }

    func testWriteWithoutDirectoryThrows() {
        XCTAssertThrowsError(try SafetyCopies.write(Data("x".utf8), kind: .preRestore, directory: nil))
    }

    func testDeleteRemovesOneCopyAndRefusesOtherFiles() throws {
        let keep = try place(.preRestore, daysAgo: 2)
        let gone = try place(.preRestore, daysAgo: 1)
        let raw = directory.appendingPathComponent(LegacySnapshot.fileName)
        try Data("raw".utf8).write(to: raw)

        try SafetyCopies.delete(gone, directory: directory)
        XCTAssertEqual(list().map(\.url.lastPathComponent), [keep.lastPathComponent])

        XCTAssertThrowsError(try SafetyCopies.delete(raw, directory: directory), "only safety copies can be deleted here")
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent(keep.lastPathComponent)
        XCTAssertThrowsError(try SafetyCopies.delete(elsewhere, directory: directory))
        XCTAssertThrowsError(try SafetyCopies.delete(gone, directory: directory), "a copy that is already gone is reported")
    }

    func testDeleteSurfacesFileSystemError() throws {
        let url = try place(.preRestore, daysAgo: 1)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try SafetyCopies.delete(url, directory: directory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: Retention

    func testPruneKeepsNewestThreePreRestoreCopies() throws {
        for daysAgo in [1.0, 2, 3, 4, 5] { try place(.preRestore, daysAgo: daysAgo) }
        try place(.preUpdate, daysAgo: 2)

        prune()
        XCTAssertEqual(list().filter { $0.kind == .preRestore }.count, 3)
        XCTAssertEqual(ages(list().filter { $0.kind == .preRestore }), [1, 2, 3])
        XCTAssertEqual(list().filter { $0.kind == .preUpdate }.count, 1, "the pre-update copy does not count toward the three")

        // Every write prunes once it has succeeded: the oldest of the four goes.
        try SafetyCopies.write(Data("new".utf8), kind: .preRestore, date: now, now: now,
                               directory: directory)
        XCTAssertEqual(ages(list().filter { $0.kind == .preRestore }), [0, 1, 2])
    }

    func testPruneRemovesCopiesOlderThan30Days() throws {
        try place(.preRestore, daysAgo: 29)
        try place(.preRestore, daysAgo: 31)
        try place(.preRestore, daysAgo: 60)

        prune()
        XCTAssertEqual(ages(list()), [29])
    }

    /// Spec: the copy from before the update is never deleted automatically. Only the user's Delete removes it,
    /// however old it is and whether or not a backup has been made since.
    func testPreUpdateCopyIsNeverPrunedAutomatically() throws {
        let old = try place(.preUpdate, daysAgo: 400)
        let older = try place(.preUpdate, daysAgo: 800)
        try place(.preRestore, daysAgo: 31)

        prune()
        XCTAssertEqual(list().map(\.kind), [.preUpdate, .preUpdate], "pre-update copies stay; the stale pre-restore copy goes")
        XCTAssertEqual(ages(list()), [400, 800])

        // Writes prune too; a new pre-restore copy does not take the pre-update copies with it.
        try SafetyCopies.write(Data("new".utf8), kind: .preRestore, date: now, now: now, directory: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: older.path))

        // The user can still delete it.
        try SafetyCopies.delete(old, directory: directory)
        XCTAssertEqual(list().map(\.kind), [.preRestore, .preUpdate])
    }

    func testPruneNeverRemovesFileBeingRestored() throws {
        let oldest = try place(.preRestore, daysAgo: 3)
        try place(.preRestore, daysAgo: 2)
        try place(.preRestore, daysAgo: 1)

        try SafetyCopies.write(Data("new".utf8), kind: .preRestore, date: now, now: now,
                               directory: directory, protecting: [oldest])
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldest.path), "the copy being restored is kept")
        XCTAssertEqual(list().count, 4)

        // A later prune (next launch) applies the limit again.
        prune()
        XCTAssertEqual(ages(list()), [0, 1, 2])
    }

    // MARK: Pre-update conversion

    private func makeRawSnapshot(events: Data?, archived: Data?) throws -> URL {
        if let events { defaults.set(events, forKey: PersistenceKeys.events) }
        if let archived { defaults.set(archived, forKey: PersistenceKeys.archivedData) }
        return try XCTUnwrap(LegacySnapshot.writeIfNeeded(defaults: defaults, legacy: legacy,
                                                          directory: directory, flagKey: rawFlagKey))
    }

    func testLegacyRawSnapshotConvertsOnceToRhythmxAndRawRemoved() throws {
        let day1 = Date(timeIntervalSince1970: 1_750_000_000)
        let events = [
            Event(id: "e1", eventType: .menstrual, date: day1, note: "one"),
            Event(id: "e2", eventType: .luteal, date: day1.addingTimeInterval(day * 20), note: "")
        ]
        let block = ArchivedDataBlock(date: day1.addingTimeInterval(-day * 28), groupedEvents: [
            .init(eventType: .menstrual, events: [Event(id: "a1", eventType: .menstrual, date: day1.addingTimeInterval(-day * 28), note: "")])
        ])
        let raw = try makeRawSnapshot(events: try JSONEncoder().encode(events),
                                      archived: try JSONEncoder().encode([block]))
        let rawCreatedAt = try XCTUnwrap(LegacySnapshot.read(directory: directory)).createdAt

        let url = try XCTUnwrap(convert())

        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path), "the raw file is removed once the copy exists")
        XCTAssertTrue(defaults.bool(forKey: convertedFlagKey))
        let copies = list()
        XCTAssertEqual(copies.map(\.kind), [.preUpdate])
        XCTAssertEqual(copies.first?.url.lastPathComponent, url.lastPathComponent)
        XCTAssertEqual(try XCTUnwrap(copies.first?.date).timeIntervalSince(rawCreatedAt), 0, accuracy: 1,
                       "the copy is dated when the raw snapshot was taken")
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)

        let data = try Data(contentsOf: url)
        XCTAssertFalse(try BackupFile.inspect(data).isEncrypted)
        let payload = try BackupFile.open(data, passphrase: nil)
        XCTAssertEqual(payload.events.map(\.id), ["e1", "e2"])
        XCTAssertEqual(payload.events.first?.note, "one")
        XCTAssertEqual(payload.archivedBlocks.map(\.id), [block.id])
        XCTAssertEqual(payload.archivedBlocks.first?.groupedEvents.first?.events.map(\.id), ["a1"])
        XCTAssertEqual(payload.settings, settings)

        // Runs once.
        XCTAssertNil(convert())
        XCTAssertEqual(list().count, 1)
    }

    func testLegacyConversionSurvivesThePruneThatFollowsIt() throws {
        // The snapshot was taken long ago (the user updated, then did not open the app for a year) and
        // three newer pre-restore copies exist: the prune after conversion must not touch the new copy.
        let events = [Event(id: "e1", eventType: .menstrual, date: now, note: "")]
        _ = try makeRawSnapshot(events: try JSONEncoder().encode(events), archived: nil)
        for daysAgo in [1.0, 2, 3] { try place(.preRestore, daysAgo: daysAgo) }

        let url = try XCTUnwrap(SafetyCopies.convertLegacySnapshotIfNeeded(
            defaults: defaults, directory: directory, flagKey: convertedFlagKey,
            settings: settings, appVersion: "2.0-test", now: now.addingTimeInterval(400 * day)
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(list().filter { $0.kind == .preUpdate }.map(\.url), [url])
        XCTAssertFalse(LegacySnapshot.exists(directory: directory))
    }

    func testLegacyConversionWithOnlyEventsUsesEmptyArchive() throws {
        let events = [Event(id: "e1", eventType: .menstrual, date: now, note: "")]
        _ = try makeRawSnapshot(events: try JSONEncoder().encode(events), archived: nil)
        let url = try XCTUnwrap(convert())
        let payload = try BackupFile.open(Data(contentsOf: url), passphrase: nil)
        XCTAssertEqual(payload.events.map(\.id), ["e1"])
        XCTAssertTrue(payload.archivedBlocks.isEmpty)
    }

    func testLegacyConversionFailureKeepsRawFileAndDoesNotCrash() throws {
        // Events decode, the archive blob does not: nothing is converted, so no cycles are lost.
        let events = [Event(id: "e1", eventType: .menstrual, date: now, note: "")]
        let raw = try makeRawSnapshot(events: try JSONEncoder().encode(events), archived: Data("not json".utf8))
        let before = try Data(contentsOf: raw)

        XCTAssertNil(convert())
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertEqual(try Data(contentsOf: raw), before, "the raw file is untouched")
        XCTAssertFalse(defaults.bool(forKey: convertedFlagKey), "the next launch tries again")
        XCTAssertTrue(list().isEmpty)

        // The raw file itself is unreadable: same outcome.
        try Data("garbage".utf8).write(to: raw)
        XCTAssertNil(convert())
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertFalse(defaults.bool(forKey: convertedFlagKey))

        // No raw file at all (a fresh install): nothing to do, and the flag stays clear.
        try FileManager.default.removeItem(at: raw)
        XCTAssertNil(convert())
        XCTAssertFalse(defaults.bool(forKey: convertedFlagKey))
    }
}
