import XCTest
@testable import RhythmX

final class AppGroupMigrationTests: XCTestCase {
    private var legacy: UserDefaults!
    private var group: UserDefaults!

    override func setUp() {
        super.setUp()
        for name in ["test.legacy", "test.group"] {
            UserDefaults(suiteName: name)!.removePersistentDomain(forName: name)
        }
        legacy = UserDefaults(suiteName: "test.legacy")!
        group = UserDefaults(suiteName: "test.group")!
    }

    func testCopiesLegacyKeysOnce() {
        legacy.set(Data("E".utf8), forKey: PersistenceKeys.events)
        legacy.set(Data("A".utf8), forKey: PersistenceKeys.archivedData)
        legacy.set("#112233", forKey: "phaseColor1")

        AppGroup.migrateIfNeeded(from: legacy, to: group)

        XCTAssertEqual(group.data(forKey: PersistenceKeys.events), Data("E".utf8))
        XCTAssertEqual(group.data(forKey: PersistenceKeys.archivedData), Data("A".utf8))
        XCTAssertEqual(group.string(forKey: "phaseColor1"), "#112233")
        XCTAssertNotNil(legacy.data(forKey: PersistenceKeys.events), "legacy keys must be kept")
    }

    func testSecondRunDoesNothing() {
        legacy.set(Data("E1".utf8), forKey: PersistenceKeys.events)
        AppGroup.migrateIfNeeded(from: legacy, to: group)
        legacy.set(Data("E2".utf8), forKey: PersistenceKeys.events)
        AppGroup.migrateIfNeeded(from: legacy, to: group)
        XCTAssertEqual(group.data(forKey: PersistenceKeys.events), Data("E1".utf8))
    }

    func testDoesNotOverwriteExistingGroupData() {
        group.set(Data("G".utf8), forKey: PersistenceKeys.events)
        legacy.set(Data("L".utf8), forKey: PersistenceKeys.events)
        AppGroup.migrateIfNeeded(from: legacy, to: group)
        XCTAssertEqual(group.data(forKey: PersistenceKeys.events), Data("G".utf8))
    }

    func testFreshInstallCopiesNothing() {
        AppGroup.migrateIfNeeded(from: legacy, to: group)
        XCTAssertNil(group.data(forKey: PersistenceKeys.events))
    }

    func testEmptyLegacyDoesNotLockOutLaterMigration() {
        AppGroup.migrateIfNeeded(from: legacy, to: group)   // legacy unreadable/empty at first launch
        legacy.set(Data("E".utf8), forKey: PersistenceKeys.events)
        AppGroup.migrateIfNeeded(from: legacy, to: group)
        XCTAssertEqual(group.data(forKey: PersistenceKeys.events), Data("E".utf8))
    }
}
