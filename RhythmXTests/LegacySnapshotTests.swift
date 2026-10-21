import XCTest
@testable import RhythmX

final class LegacySnapshotTests: XCTestCase {
    private let suiteName = "test.legacySnapshot"
    private let legacySuiteName = "test.legacySnapshot.standard"
    private let flagKey = "test.legacySnapshotFlag"
    private var defaults: UserDefaults!
    /// Stands in for UserDefaults.standard, the pre-App-Group store.
    private var legacy: UserDefaults!
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
        UserDefaults(suiteName: legacySuiteName)!.removePersistentDomain(forName: legacySuiteName)
        legacy = UserDefaults(suiteName: legacySuiteName)!
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacySnapshotTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
        UserDefaults(suiteName: legacySuiteName)!.removePersistentDomain(forName: legacySuiteName)
        try super.tearDownWithError()
    }

    private func write(directory chosen: URL?? = nil) -> URL? {
        LegacySnapshot.writeIfNeeded(defaults: defaults, legacy: legacy,
                                     directory: chosen ?? directory, flagKey: flagKey)
    }

    private struct SnapshotFile: Decodable {
        let events: String?
        let archivedData: String?
        let createdAt: Date
    }

    private func readFile(_ url: URL) throws -> SnapshotFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SnapshotFile.self, from: Data(contentsOf: url))
    }

    func testWritesRawCopyOnce() throws {
        let events = Data([0x00, 0x01, 0xFF, 0x7B, 0x22, 0x65, 0x22, 0x7D])
        let archived = Data("archived-blob-\u{00E9}".utf8)
        defaults.set(events, forKey: PersistenceKeys.events)
        defaults.set(archived, forKey: PersistenceKeys.archivedData)

        let url = try XCTUnwrap(write())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(LegacySnapshot.exists(directory: directory))
        XCTAssertTrue(defaults.bool(forKey: flagKey))

        let first = try readFile(url)
        XCTAssertEqual(first.events.flatMap { Data(base64Encoded: $0) }, events)
        XCTAssertEqual(first.archivedData.flatMap { Data(base64Encoded: $0) }, archived)
        XCTAssertEqual(first.createdAt.timeIntervalSinceNow, 0, accuracy: 60)

        // Data changes after the snapshot; the second call must not rewrite the file.
        defaults.set(Data("changed".utf8), forKey: PersistenceKeys.events)
        XCTAssertNil(write())
        let second = try readFile(url)
        XCTAssertEqual(second.events.flatMap { Data(base64Encoded: $0) }, events)
        XCTAssertEqual(second.archivedData.flatMap { Data(base64Encoded: $0) }, archived)
        XCTAssertEqual(second.createdAt, first.createdAt)
    }

    /// A fresh 2.0 install has nothing under either key in either store. There is no 1.9.x data to protect,
    /// so the flag is set right away: the data the user logs in 2.0 must never be snapshotted on launch 2
    /// and shown as a copy "from before the update".
    func testFreshInstallSetsFlagSoLaterDataIsNeverSnapshotted() throws {
        XCTAssertNil(write())
        XCTAssertTrue(defaults.bool(forKey: flagKey), "nothing to protect: done")
        XCTAssertFalse(LegacySnapshot.exists(directory: directory))

        // Launch 2: the user has logged 2.0 data. No snapshot.
        defaults.set(Data("E".utf8), forKey: PersistenceKeys.events)
        defaults.set(Data("A".utf8), forKey: PersistenceKeys.archivedData)
        XCTAssertNil(write())
        XCTAssertFalse(LegacySnapshot.exists(directory: directory))
    }

    /// The other side of the same rule: a phone that really has 1.9.x data, in either store, is snapshotted.
    func testRealLegacyDataIsSnapshottedOnFirstLaunch() throws {
        legacy.set(Data("E".utf8), forKey: PersistenceKeys.events)

        let url = try XCTUnwrap(write(), "data in the old standard store counts")
        let file = try readFile(url)
        XCTAssertEqual(file.events.flatMap { Data(base64Encoded: $0) }, Data("E".utf8))
        XCTAssertNil(file.archivedData)
        XCTAssertTrue(defaults.bool(forKey: flagKey))

        // Archive only, in the App Group store, on another fresh set of defaults: also snapshotted.
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
        UserDefaults(suiteName: legacySuiteName)!.removePersistentDomain(forName: legacySuiteName)
        try LegacySnapshot.delete(directory: directory)
        defaults.set(Data("A".utf8), forKey: PersistenceKeys.archivedData)
        let second = try readFile(try XCTUnwrap(write(), "archive data alone counts"))
        XCTAssertNil(second.events)
        XCTAssertEqual(second.archivedData.flatMap { Data(base64Encoded: $0) }, Data("A".utf8))
    }

    func testDeleteRemovesFile() throws {
        defaults.set(Data("E".utf8), forKey: PersistenceKeys.events)
        let url = try XCTUnwrap(write())
        XCTAssertTrue(LegacySnapshot.exists(directory: directory))

        try LegacySnapshot.delete(directory: directory)

        XCTAssertFalse(LegacySnapshot.exists(directory: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNoThrow(try LegacySnapshot.delete(directory: directory), "deleting an absent snapshot is not an error")
        // The flag stays set: deletion is the user's choice and must not trigger a fresh snapshot of migrated data.
        XCTAssertNil(write())
    }

    func testFileIsExcludedFromBackup() throws {
        defaults.set(Data("E".utf8), forKey: PersistenceKeys.events)
        let url = try XCTUnwrap(write())
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testDefaultDirectoryIsInApplicationSupport() throws {
        let appSupport = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: false)
        let directory = try XCTUnwrap(LegacySnapshot.defaultDirectory)
        XCTAssertTrue(directory.standardizedFileURL.path.hasPrefix(appSupport.standardizedFileURL.path))
    }

    func testFallsBackToStandardDefaultsWhenGroupHasNoData() throws {
        // The App Group copy has not happened yet: events live only in the old standard store.
        legacy.set(Data("standard-events".utf8), forKey: PersistenceKeys.events)
        defaults.set(Data("group-archive".utf8), forKey: PersistenceKeys.archivedData)

        let url = try XCTUnwrap(write())
        let file = try readFile(url)
        XCTAssertEqual(file.events.flatMap { Data(base64Encoded: $0) }, Data("standard-events".utf8))
        XCTAssertEqual(file.archivedData.flatMap { Data(base64Encoded: $0) }, Data("group-archive".utf8))
    }

    func testGroupDataWinsOverStandardDefaults() throws {
        legacy.set(Data("standard-events".utf8), forKey: PersistenceKeys.events)
        defaults.set(Data("group-events".utf8), forKey: PersistenceKeys.events)

        let file = try readFile(try XCTUnwrap(write()))
        XCTAssertEqual(file.events.flatMap { Data(base64Encoded: $0) }, Data("group-events".utf8))
    }

    func testNoDirectoryWritesNothingAndRetriesNextLaunch() throws {
        defaults.set(Data("E".utf8), forKey: PersistenceKeys.events)
        XCTAssertNil(write(directory: .some(nil)), "no Application Support means no snapshot, never a temporary copy")
        XCTAssertFalse(defaults.bool(forKey: flagKey))
        XCTAssertNotNil(write(), "the next launch with a directory writes it")
    }
}
