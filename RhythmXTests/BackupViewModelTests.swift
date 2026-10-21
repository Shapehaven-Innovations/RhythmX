import XCTest
@testable import RhythmX

@MainActor
final class BackupViewModelTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    /// Keys AppSettings writes; saved and restored around each test so real values survive.
    private let groupSettingKeys = ["phaseColor1", "phaseColor2", "phaseColor3", "phaseColor4"]
    private let standardSettingKeys = ["notificationsEnabled", "notifyDayBefore", "notifyDayOf"]
    private var savedGroup: [String: Any] = [:]
    private var savedStandard: [String: Any] = [:]

    private var events: EventStore!
    private var archived: ArchivedDataStore!
    private var settings: AppSettings!
    private var defaults: UserDefaults!
    private var defaultsSuite: String!
    private var exportDirectory: URL!
    private var safetyDirectory: URL!
    /// What the view model's `now` returns; tests move it forward to space copies apart.
    private var clock: Date!

    override func setUp() {
        super.setUp()
        savedGroup = [:]
        savedStandard = [:]
        for key in groupSettingKeys { savedGroup[key] = AppGroup.defaults.object(forKey: key) }
        for key in standardSettingKeys { savedStandard[key] = UserDefaults.standard.object(forKey: key) }
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.events)
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.archivedData)
        events = EventStore()
        archived = ArchivedDataStore()
        settings = AppSettings()
        defaultsSuite = "BackupViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)
        exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupViewModelTests-\(UUID().uuidString)", isDirectory: true)
        safetyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupViewModelTests-safety-\(UUID().uuidString)", isDirectory: true)
        clock = base
    }

    override func tearDown() {
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.events)
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.archivedData)
        for key in groupSettingKeys { AppGroup.defaults.set(savedGroup[key], forKey: key) }
        for key in standardSettingKeys { UserDefaults.standard.set(savedStandard[key], forKey: key) }
        defaults.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: exportDirectory)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safetyDirectory.path)
        try? FileManager.default.removeItem(at: safetyDirectory)
        super.tearDown()
    }

    private func makeModel(safetyDirectory chosen: URL?? = nil) -> BackupViewModel {
        BackupViewModel(
            events: events,
            archived: archived,
            settings: settings,
            defaults: defaults,
            exportDirectory: exportDirectory,
            safetyDirectory: chosen ?? safetyDirectory,
            appVersion: "2.0-test",
            iterations: 1_000,
            now: { [unowned self] in self.clock }
        )
    }

    func testCreateBackupWritesReadableFileAndSetsLastBackupDate() async throws {
        events.add(Event(id: "e1", eventType: .menstrual, date: base, note: "first"))
        events.add(Event(id: "e2", eventType: .luteal, date: base.addingTimeInterval(86_400 * 20), note: ""))
        let model = makeModel()
        XCTAssertNil(model.lastBackupDate)

        let url = try await model.createBackup(passphrase: "secret")
        XCTAssertFalse(model.isWorking)

        XCTAssertEqual(url.pathExtension, "rhythmx")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(url.lastPathComponent, "RhythmX-\(formatter.string(from: base)).rhythmx")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, exportDirectory.standardizedFileURL)

        let data = try Data(contentsOf: url)
        let header = try BackupFile.inspect(data)
        XCTAssertTrue(header.isEncrypted)
        XCTAssertEqual(header.appVersion, "2.0-test")
        let payload = try BackupFile.open(data, passphrase: "secret")
        XCTAssertEqual(Set(payload.events.map(\.id)), ["e1", "e2"])

        XCTAssertEqual(model.lastBackupDate, base)
        XCTAssertEqual(defaults.object(forKey: BackupViewModel.lastBackupDateKey) as? Date, base)
        XCTAssertEqual(makeModel().lastBackupDate, base, "a new model reads the stored date")

        // The view model can open what it wrote.
        let opener = makeModel()
        let loaded = try opener.loadFile(url)
        XCTAssertTrue(loaded.isEncrypted)
        do {
            _ = try await opener.unlock(passphrase: "nope")
            XCTFail("a wrong passphrase must throw")
        } catch {
            XCTAssertEqual(error as? BackupFileError, .wrongPassphrase)
        }
        XCTAssertFalse(opener.isWorking)
        let preview = try await opener.unlock(passphrase: "secret")
        XCTAssertEqual(preview.eventCount, 2)

        // An empty passphrase means no passphrase: the file is written unencrypted
        // (same date, so it replaces the earlier export).
        let plainURL = try await model.createBackup(passphrase: "")
        XCTAssertEqual(plainURL, url)
        XCTAssertFalse(try BackupFile.inspect(Data(contentsOf: plainURL)).isEncrypted)
    }

    func testRestoreMergeDefaultsAndReplaceNeedsExplicitCall() async throws {
        // A file holding one event that clashes by id and one new event.
        let source = makeModel()
        events.add(Event(id: "keep", eventType: .menstrual, date: base, note: "in file"))
        events.add(Event(id: "new", eventType: .follicular, date: base.addingTimeInterval(86_400 * 8), note: ""))
        let url = try await source.createBackup(passphrase: nil)

        // The phone now holds different data.
        events.replaceAll([
            Event(id: "keep", eventType: .menstrual, date: base, note: "on phone"),
            Event(id: "local", eventType: .luteal, date: base.addingTimeInterval(86_400 * 22), note: "")
        ])

        let model = makeModel()
        XCTAssertEqual(model.selectedMode, .merge, "Merge is the default")
        let header = try model.loadFile(url)
        XCTAssertFalse(header.isEncrypted)
        _ = try await model.unlock(passphrase: nil)

        let merged = try model.restore(model.selectedMode)
        XCTAssertEqual(merged, RestoreResult(eventsAdded: 1, blocksAdded: 0))
        XCTAssertEqual(Set(events.events.map(\.id)), ["keep", "local", "new"])
        XCTAssertEqual(events.events.first { $0.id == "keep" }?.note, "on phone")

        // Replace happens only when asked for by name.
        let replaced = try model.restore(.replace)
        XCTAssertEqual(replaced, RestoreResult(eventsAdded: 2, blocksAdded: 0))
        XCTAssertEqual(Set(events.events.map(\.id)), ["keep", "new"])
        XCTAssertEqual(events.events.first { $0.id == "keep" }?.note, "in file")
    }

    func testLoadFileOfPlainTextThrowsNotABackup() throws {
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let url = exportDirectory.appendingPathComponent("notes.rhythmx")
        try Data("Just some notes, not a backup.".utf8).write(to: url)

        let model = makeModel()
        XCTAssertThrowsError(try model.loadFile(url)) { error in
            XCTAssertEqual(error as? BackupFileError, .notABackup)
        }
        XCTAssertNil(model.header)
        XCTAssertNil(model.preview)

        XCTAssertEqual(BackupViewModel.message(for: BackupFileError.notABackup), "That file isn't a RhythmX backup.")
        XCTAssertEqual(BackupViewModel.message(for: BackupFileError.newerFormat(3)),
                       "This backup was made by a newer version of RhythmX. Update the app to open it.")
        XCTAssertEqual(BackupViewModel.message(for: BackupFileError.wrongPassphrase), "Wrong passphrase.")
        XCTAssertEqual(BackupViewModel.message(for: BackupFileError.corrupted), "This file looks damaged and was not restored.")
    }

    func testFileThatCannotBeReadIsReportedAsUnreadableNotDamaged() throws {
        // The file is gone (or iCloud has not downloaded it, or access was denied): nothing says it is damaged.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupViewModelTests-missing-\(UUID().uuidString).rhythmx")
        let model = makeModel()
        XCTAssertThrowsError(try model.loadFile(missing)) { error in
            XCTAssertEqual(error as? BackupViewModel.RestoreError, .unreadableFile)
        }
        XCTAssertNil(model.header)
        XCTAssertEqual(BackupViewModel.message(for: BackupViewModel.RestoreError.unreadableFile),
                       "This file could not be opened. Make sure it has finished downloading and try again.")
        XCTAssertNotEqual(BackupViewModel.message(for: BackupViewModel.RestoreError.unreadableFile),
                          BackupViewModel.message(for: BackupFileError.corrupted))
    }

    // MARK: - Safety copy before Replace

    private func loadedModel(fileEvents: [Event], phoneEvents: [Event], safetyDirectory chosen: URL?? = nil) async throws -> BackupViewModel {
        events.replaceAll(fileEvents)
        let url = try await makeModel().createBackup(passphrase: nil)
        events.replaceAll(phoneEvents)
        let model = makeModel(safetyDirectory: chosen)
        _ = try model.loadFile(url)
        _ = try await model.unlock(passphrase: nil)
        return model
    }

    func testReplaceWritesPreRestoreCopyOfCurrentData() async throws {
        let model = try await loadedModel(
            fileEvents: [Event(id: "fromFile", eventType: .menstrual, date: base, note: "file")],
            phoneEvents: [Event(id: "old", eventType: .luteal, date: base, note: "phone")]
        )

        // Merge never needs a safety copy.
        try model.restore(.merge)
        XCTAssertTrue(SafetyCopies.list(directory: safetyDirectory).isEmpty)

        try model.restore(.replace)

        XCTAssertEqual(events.events.map(\.id), ["fromFile"])
        let copies = SafetyCopies.list(directory: safetyDirectory)
        XCTAssertEqual(copies.map(\.kind), [.preRestore])
        let copy = try XCTUnwrap(copies.first?.url)
        XCTAssertEqual(copy.lastPathComponent, SafetyCopies.fileName(kind: .preRestore, date: base))
        XCTAssertEqual(try copy.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let data = try Data(contentsOf: copy)
        XCTAssertFalse(try BackupFile.inspect(data).isEncrypted)
        let saved = try BackupFile.open(data, passphrase: nil)
        XCTAssertEqual(Set(saved.events.map(\.id)), ["old", "fromFile"], "the copy holds the data as it was right before Replace")
        XCTAssertEqual(saved.events.first { $0.id == "old" }?.note, "phone")
    }

    func testReplaceIsBlockedWhenSafetyCopyCannotBeWritten() async throws {
        // A regular file where the directory should be makes the write fail.
        let blocker: URL = safetyDirectory
        try Data("x".utf8).write(to: blocker)
        let model = try await loadedModel(
            fileEvents: [Event(id: "fromFile", eventType: .menstrual, date: base, note: "file")],
            phoneEvents: [Event(id: "old", eventType: .luteal, date: base, note: "phone")],
            safetyDirectory: blocker.appendingPathComponent("Backup", isDirectory: true)
        )
        settings.notifyDayBefore.toggle()
        let changedSetting = settings.notifyDayBefore

        XCTAssertThrowsError(try model.restore(.replace)) { error in
            XCTAssertEqual(error as? BackupViewModel.RestoreError, .safetyCopyFailed)
        }
        XCTAssertEqual(events.events.map(\.id), ["old"])
        XCTAssertEqual(events.events.first?.note, "phone")
        XCTAssertEqual(settings.notifyDayBefore, changedSetting, "settings are left as they were")
        XCTAssertEqual(BackupViewModel.message(for: BackupViewModel.RestoreError.safetyCopyFailed),
                       "A safety copy of your current data could not be saved, so nothing was replaced. Your data has not changed.")

        // No Application Support directory at all: also blocked.
        let noDirectory = try await loadedModel(
            fileEvents: [Event(id: "fromFile", eventType: .menstrual, date: base, note: "file")],
            phoneEvents: [Event(id: "old", eventType: .luteal, date: base, note: "phone")],
            safetyDirectory: .some(nil)
        )
        XCTAssertThrowsError(try noDirectory.restore(.replace))
        XCTAssertEqual(events.events.map(\.id), ["old"])
    }

    func testRestoreOfRestoreWritesNewCopy() async throws {
        let model = try await loadedModel(
            fileEvents: [Event(id: "fromFile", eventType: .menstrual, date: base, note: "file")],
            phoneEvents: [Event(id: "original", eventType: .luteal, date: base, note: "phone")]
        )
        try model.restore(.replace)
        let first = try XCTUnwrap(SafetyCopies.list(directory: safetyDirectory).first)
        XCTAssertEqual(events.events.map(\.id), ["fromFile"])

        // Undo: restore the copy saved before the Replace, through the same flow as any file.
        clock = base.addingTimeInterval(3_600)
        let undo = makeModel()
        _ = try undo.loadFile(first.url)
        _ = try await undo.unlock(passphrase: nil)
        try undo.restore(.replace)

        XCTAssertEqual(events.events.map(\.id), ["original"])
        XCTAssertEqual(events.events.first?.note, "phone")
        let copies = SafetyCopies.list(directory: safetyDirectory)
        XCTAssertEqual(copies.count, 2, "undoing a Replace saves its own copy, so the undo can be undone")
        XCTAssertEqual(copies.first?.date, clock)
        XCTAssertEqual(copies.last?.url.lastPathComponent, first.url.lastPathComponent)
        let second = try BackupFile.open(Data(contentsOf: try XCTUnwrap(copies.first?.url)), passphrase: nil)
        XCTAssertEqual(second.events.map(\.id), ["fromFile"], "the new copy holds the data from right before the undo")
    }

    func testPruneNeverRemovesFileBeingRestored() async throws {
        // Three copies already exist; the user restores the oldest.
        try FileManager.default.createDirectory(at: safetyDirectory, withIntermediateDirectories: true)
        var oldest: URL?
        for (index, id) in ["oldest", "middle", "newest"].enumerated() {
            let date = base.addingTimeInterval(Double(index - 3) * 86_400)
            let payload = BackupPayload(events: [Event(id: id, eventType: .menstrual, date: date, note: "")],
                                        archivedBlocks: [], settings: settings.settingsSnapshot())
            let data = try BackupFile.make(payload, appVersion: "2.0-test", passphrase: nil, now: date)
            let url = safetyDirectory.appendingPathComponent(SafetyCopies.fileName(kind: .preRestore, date: date))
            try data.write(to: url)
            if index == 0 { oldest = url }
        }
        let oldestURL = try XCTUnwrap(oldest)
        events.replaceAll([Event(id: "current", eventType: .luteal, date: base, note: "")])

        let model = makeModel()
        _ = try model.loadFile(oldestURL)
        _ = try await model.unlock(passphrase: nil)
        try model.restore(.replace)

        XCTAssertEqual(events.events.map(\.id), ["oldest"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldestURL.path), "the file being restored is not pruned")
        let copies = SafetyCopies.list(directory: safetyDirectory)
        XCTAssertEqual(copies.count, 4)
        XCTAssertEqual(copies.first?.date, base, "the new pre-restore copy was written")
    }

    // MARK: - Saved copies list

    func testSavedCopiesListShowsKindsAndCounts() async throws {
        let model = try await loadedModel(
            fileEvents: [Event(id: "fromFile", eventType: .menstrual, date: base, note: "file")],
            phoneEvents: [Event(id: "a", eventType: .luteal, date: base, note: ""),
                          Event(id: "b", eventType: .menstrual, date: base, note: "")]
        )
        try model.restore(.replace)
        // An unreadable copy is still listed so it can be deleted.
        try Data("broken".utf8).write(to: safetyDirectory.appendingPathComponent(
            SafetyCopies.fileName(kind: .preUpdate, date: base.addingTimeInterval(-86_400))))

        await model.refreshSavedCopies()

        XCTAssertEqual(model.savedCopies.map(\.copy.kind), [.preRestore, .preUpdate])
        XCTAssertEqual(model.savedCopies.first?.preview?.eventCount, 2)
        XCTAssertEqual(model.savedCopies.first?.preview?.cycleCount, 0)
        XCTAssertNil(model.savedCopies.last?.preview)
        XCTAssertEqual(BackupViewModel.label(for: .preUpdate), "Before the update")
        XCTAssertEqual(BackupViewModel.label(for: .preRestore), "Before a restore")
    }

    func testDeleteSurfacesError() async throws {
        let model = try await loadedModel(
            fileEvents: [Event(id: "fromFile", eventType: .menstrual, date: base, note: "file")],
            phoneEvents: [Event(id: "old", eventType: .luteal, date: base, note: "phone")]
        )
        try model.restore(.replace)
        await model.refreshSavedCopies()
        let copy = try XCTUnwrap(model.savedCopies.first?.copy)

        // A folder that cannot be changed makes the delete fail.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: safetyDirectory.path)
        await model.deleteSavedCopy(copy)
        XCTAssertEqual(model.savedCopiesError, "This copy could not be deleted. Try again.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.url.path))
        XCTAssertEqual(model.savedCopies.count, 1)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safetyDirectory.path)
        await model.deleteSavedCopy(copy)
        XCTAssertNil(model.savedCopiesError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.url.path))
        XCTAssertTrue(model.savedCopies.isEmpty)
    }

    // MARK: - Inbox and exports

    func testLoadFileDeletesInboxCopyAfterReading() async throws {
        events.add(Event(id: "e1", eventType: .menstrual, date: base, note: ""))
        let url = try await makeModel().createBackup(passphrase: nil)

        let inbox = exportDirectory.appendingPathComponent("App/Documents/Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let inboxURL = inbox.appendingPathComponent("RhythmX-copy.rhythmx")
        try FileManager.default.copyItem(at: url, to: inboxURL)

        let model = makeModel()
        _ = try model.loadFile(inboxURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxURL.path), "the inbox copy is removed once read")
        let preview = try await model.unlock(passphrase: nil)
        XCTAssertEqual(preview.eventCount, 1, "the file was read before it was removed")

        // A file the user picked elsewhere is left alone.
        _ = try makeModel().loadFile(url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testStaticClearExportsRemovesExportDirectory() throws {
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: exportDirectory.appendingPathComponent("RhythmX-old.rhythmx"))

        BackupViewModel.clearExports(at: exportDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: exportDirectory.path))
        XCTAssertEqual(BackupViewModel.defaultExportDirectory.lastPathComponent, "RhythmXBackupExport")
    }

    func testFailedUnlockLeavesStoresUntouched() async throws {
        events.replaceAll([Event(id: "keep", eventType: .menstrual, date: base, note: "phone")])
        let url = try await makeModel().createBackup(passphrase: "secret")
        events.replaceAll([Event(id: "phone", eventType: .luteal, date: base, note: "phone")])

        let model = makeModel()
        _ = try model.loadFile(url)
        do {
            _ = try await model.unlock(passphrase: "wrong")
            XCTFail("expected wrong passphrase")
        } catch {}
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.preview)
        XCTAssertEqual(try model.restore(.replace), RestoreResult(eventsAdded: 0, blocksAdded: 0))
        XCTAssertEqual(events.events.map(\.id), ["phone"])
    }
}
