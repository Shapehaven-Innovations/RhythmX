import XCTest
@testable import RhythmX

@MainActor
final class BackupServiceTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    /// Keys AppSettings writes; saved and restored around each test so real values survive.
    private let groupSettingKeys = ["phaseColor1", "phaseColor2", "phaseColor3", "phaseColor4",
                                    "trackingMode", "defaultModeOnLaunch"]
    private let standardSettingKeys = ["notificationsEnabled", "notifyDayBefore", "notifyDayOf",
                                       "fertileStartOn", "fertileOvulationOn",
                                       "loggingReminders", "dailyCheckIn", "weeklyCheckIn"]
    private var savedGroup: [String: Any] = [:]
    private var savedStandard: [String: Any] = [:]

    private var events: EventStore!
    private var archived: ArchivedDataStore!
    private var settings: AppSettings!

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
    }

    override func tearDown() {
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.events)
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.archivedData)
        for key in groupSettingKeys { AppGroup.defaults.set(savedGroup[key], forKey: key) }
        for key in standardSettingKeys { UserDefaults.standard.set(savedStandard[key], forKey: key) }
        super.tearDown()
    }

    // MARK: - Fixtures

    private func block(_ id: String, daysAfter: Double, events: [Event] = [], mode: TrackingMode? = nil) -> ArchivedDataBlock {
        ArchivedDataBlock(
            id: UUID(uuidString: id)!,
            date: base.addingTimeInterval(daysAfter * day),
            groupedEvents: events.isEmpty ? [] : [ArchivedDataBlock.PhaseEvents(eventType: events[0].eventType, events: events)],
            mode: mode
        )
    }

    private let idA = "AAAAAAAA-0000-0000-0000-000000000001"
    private let idB = "BBBBBBBB-0000-0000-0000-000000000002"
    private let idC = "CCCCCCCC-0000-0000-0000-000000000003"

    private func backupSettings(color: String = "#123456", notifications: Bool = true) -> BackupSettings {
        BackupSettings(
            phaseColors: [color, "#222222", "#333333", "#444444"],
            notificationsEnabled: notifications,
            notifyDayBefore: false,
            notifyDayOf: false,
            fertileStartOn: false,
            fertileOvulationOn: false,
            trackingMode: "cycle",
            defaultModeOnLaunch: "last",
            themeID: "default",
            reminders: [],
            dailyCheckIn: nil,
            weeklyCheckIn: nil
        )
    }

    private func seedExisting() {
        settings.phaseColor1 = "#AAAAAA"
        settings.notificationsEnabled = false
        settings.notifyDayBefore = true
        settings.notifyDayOf = true
        events.add(Event(id: "x1", eventType: .menstrual, date: base, note: "existing"))
        events.add(Event(id: "x2", eventType: .luteal, date: base.addingTimeInterval(20 * day), note: "existing"))
        archived.appendArchivedBlock(block(idA, daysAfter: 30))
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    // MARK: - Merge

    func testMergeSkipsExistingIdsAndSameDayTypeDuplicates() {
        seedExisting()
        let incoming = BackupPayload(
            events: [
                Event(id: "x1", eventType: .follicular, date: base.addingTimeInterval(5 * day), note: "same id"),
                // Same start-of-day and type as x1, different id and time of day.
                Event(id: "n1", eventType: .menstrual, date: base.addingTimeInterval(3_600), note: "same day+type"),
                // Same day as x1 but a different type: kept.
                Event(id: "n2", eventType: .ovulation, date: base, note: "new", mode: .planning),
                Event(id: "n3", eventType: .menstrual, date: base.addingTimeInterval(40 * day), note: "new", mode: .menopause)
            ],
            archivedBlocks: [block(idA, daysAfter: 99), block(idB, daysAfter: 60, mode: .planning)],
            settings: backupSettings()
        )

        let result = BackupService.restore(incoming, mode: .merge, events: events, archived: archived, settings: settings)

        XCTAssertEqual(result, RestoreResult(eventsAdded: 2, blocksAdded: 1))
        XCTAssertEqual(Set(events.events.map(\.id)), ["x1", "x2", "n2", "n3"])
        XCTAssertEqual(events.events.first { $0.id == "x1" }?.note, "existing")
        XCTAssertEqual(events.events.first { $0.id == "n2" }?.mode, .planning)
        XCTAssertEqual(events.events.first { $0.id == "n3" }?.mode, .menopause)
        XCTAssertEqual(archived.archivedBlocks.map(\.id.uuidString), [idB, idA]) // newest first
        XCTAssertEqual(archived.archivedBlocks.first { $0.id.uuidString == idA }?.date, base.addingTimeInterval(30 * day))
        XCTAssertEqual(archived.archivedBlocks.first { $0.id.uuidString == idB }?.mode, .planning)
    }

    func testMergeKeepsSameDayTypeEventsFromDifferentModes() {
        events.add(Event(id: "c1", eventType: .menstrual, date: base, note: "cycle"))   // nil mode counts as cycle

        let counts = events.merge([
            // Same day and type as c1 but a menopause event: kept.
            Event(id: "m1", eventType: .menstrual, date: base.addingTimeInterval(3_600), note: "menopause", mode: .menopause),
            // Same day, type and effective mode as c1: not added (it carries no tags, so nothing to merge either).
            Event(id: "c2", eventType: .menstrual, date: base.addingTimeInterval(7_200), note: "cycle again", mode: .cycle)
        ])

        XCTAssertEqual(counts, EventStore.MergeCounts(added: 1, updated: 0))
        XCTAssertEqual(Set(events.events.map(\.id)), ["c1", "m1"])
    }

    /// A same-day event that is already on the phone is not skipped outright: the tags the file has for that
    /// day are merged in. One-per-day tags are not doubled; a repeatable tag keeps the higher count of the two
    /// (multiset union), so merging the same file twice does not inflate "Hot Flashes".
    func testMergeUnionsTagsOnSameDayTypeAndMode() throws {
        let hf = "Menopause:Hot Flashes", sleep = "Menopause:Poor Sleep", fog = "Menopause:Brain Fog"
        events.add(Event(id: "m1", eventType: .follicular, date: base, note: "", tags: "\(hf), \(hf), \(sleep)", mode: .menopause))
        events.add(Event(id: "c1", eventType: .menstrual, date: base, note: "", tags: "Symptom:Cramps"))

        let counts = events.merge([
            // Same id: the phone's event stays (note and all), its tags gain what the file had.
            Event(id: "m1", eventType: .follicular, date: base.addingTimeInterval(60), note: "from file",
                  tags: "\(sleep), \(hf), \(hf), \(hf), \(fog)", mode: .menopause),
            // Same day, type and mode as c1 under another id: tags merged, no second event.
            Event(id: "c9", eventType: .menstrual, date: base.addingTimeInterval(120), note: "", tags: "Symptom:Cramps, Mood:Low"),
            // A genuinely new day.
            Event(id: "c2", eventType: .menstrual, date: base.addingTimeInterval(day), note: "", tags: "Symptom:Cramps")
        ])

        XCTAssertEqual(counts, EventStore.MergeCounts(added: 1, updated: 2))
        XCTAssertEqual(Set(events.events.map(\.id)), ["m1", "c1", "c2"])

        let m1 = try XCTUnwrap(events.events.first { $0.id == "m1" })
        XCTAssertEqual(m1.note, "", "the phone's event is the one kept")
        XCTAssertEqual(m1.date, base)
        XCTAssertEqual(TagParser.split(m1.tags), [hf, hf, sleep, hf, fog], "existing tags first, then what the file adds")
        let c1 = try XCTUnwrap(events.events.first { $0.id == "c1" })
        XCTAssertEqual(TagParser.split(c1.tags), ["Symptom:Cramps", "Mood:Low"])

        // Persisted: a store reloaded from the same defaults sees the merged tags.
        let reloaded = EventStore()
        XCTAssertEqual(TagParser.split(reloaded.events.first { $0.id == "m1" }?.tags ?? ""), [hf, hf, sleep, hf, fog])

        // Merging the same file again changes nothing and reports nothing.
        let again = events.merge([
            Event(id: "m1", eventType: .follicular, date: base, note: "", tags: "\(sleep), \(hf), \(hf), \(hf), \(fog)", mode: .menopause),
            Event(id: "c9", eventType: .menstrual, date: base, note: "", tags: "Symptom:Cramps, Mood:Low")
        ])
        XCTAssertEqual(again, EventStore.MergeCounts(added: 0, updated: 0))
        XCTAssertEqual(TagParser.split(events.events.first { $0.id == "m1" }?.tags ?? ""), [hf, hf, sleep, hf, fog])
    }

    func testRestoreMergeReportsUpdatedEventsSeparatelyFromAdded() {
        events.add(Event(id: "c1", eventType: .menstrual, date: base, note: "", tags: "Symptom:Cramps"))
        let incoming = BackupPayload(
            events: [Event(id: "c1", eventType: .menstrual, date: base, note: "", tags: "Mood:Low")],
            archivedBlocks: [],
            settings: backupSettings()
        )
        let result = BackupService.restore(incoming, mode: .merge, events: events, archived: archived, settings: settings)
        XCTAssertEqual(result, RestoreResult(eventsAdded: 0, blocksAdded: 0, eventsUpdated: 1))
        XCTAssertEqual(result.eventsAdded, 0, "a tag merge is not a new entry")
        XCTAssertEqual(RestoreResult(eventsAdded: 2, blocksAdded: 1).eventsUpdated, 0, "Replace reports no updates")
    }

    func testMergeNeverOverwritesSettings() {
        seedExisting()
        let before = settings.settingsSnapshot()
        let incoming = BackupPayload(events: [], archivedBlocks: [], settings: backupSettings(color: "#FFFFFF", notifications: true))

        _ = BackupService.restore(incoming, mode: .merge, events: events, archived: archived, settings: settings)

        XCTAssertEqual(settings.settingsSnapshot(), before)
        XCTAssertEqual(settings.phaseColor1, "#AAAAAA")
        XCTAssertFalse(settings.notificationsEnabled)
    }

    // MARK: - Replace

    func testReplaceOverwritesEventsBlocksAndSettings() {
        seedExisting()
        let purchaseKeys = ["rhythmx.test.purchase.isPlus", "rhythmx.test.purchase.dayPassExpiry"]
        AppGroup.defaults.set(true, forKey: purchaseKeys[0])
        AppGroup.defaults.set(12_345.0, forKey: purchaseKeys[1])
        defer { purchaseKeys.forEach { AppGroup.defaults.removeObject(forKey: $0) } }

        let touchable = Set([PersistenceKeys.events, PersistenceKeys.archivedData] + groupSettingKeys + standardSettingKeys)
        let groupBefore = AppGroup.defaults.dictionaryRepresentation()
        let standardBefore = UserDefaults.standard.dictionaryRepresentation()

        let incomingSettings = backupSettings(color: "#0F0F0F", notifications: true)
        let incoming = BackupPayload(
            events: [Event(id: "r1", eventType: .follicular, date: base, note: "restored", mode: .planning)],
            archivedBlocks: [block(idB, daysAfter: 10), block(idC, daysAfter: 50)],
            settings: incomingSettings
        )

        let result = BackupService.restore(incoming, mode: .replace, events: events, archived: archived, settings: settings)

        XCTAssertEqual(result, RestoreResult(eventsAdded: 1, blocksAdded: 2))
        XCTAssertEqual(events.events.map(\.id), ["r1"])
        XCTAssertEqual(events.events.first?.mode, .planning)
        XCTAssertEqual(archived.archivedBlocks.map(\.id.uuidString), [idC, idB])
        XCTAssertEqual(settings.settingsSnapshot(), incomingSettings)
        XCTAssertEqual(settings.phaseColor1, "#0F0F0F")
        XCTAssertTrue(settings.notificationsEnabled)
        XCTAssertFalse(settings.notifyDayBefore)

        XCTAssertEqual(AppGroup.defaults.bool(forKey: purchaseKeys[0]), true)
        XCTAssertEqual(AppGroup.defaults.double(forKey: purchaseKeys[1]), 12_345.0)
        for (label, before, after) in [
            ("group", groupBefore, AppGroup.defaults.dictionaryRepresentation()),
            ("standard", standardBefore, UserDefaults.standard.dictionaryRepresentation())
        ] {
            let changed = Set(before.keys).union(after.keys).filter { key in
                !touchable.contains(key) && !((before[key] as? NSObject)?.isEqual(after[key]) ?? (after[key] == nil))
            }
            XCTAssertEqual(changed, [], "\(label) defaults keys outside settings/data were touched")
        }
    }

    func testRestoreIsPersisted() {
        seedExisting()
        let incoming = BackupPayload(
            events: [Event(id: "p1", eventType: .luteal, date: base, note: "", mode: .menopause)],
            archivedBlocks: [block(idC, daysAfter: 5)],
            settings: backupSettings(color: "#ABCDEF")
        )
        _ = BackupService.restore(incoming, mode: .replace, events: events, archived: archived, settings: settings)

        let reloadedEvents = EventStore()
        let reloadedArchive = ArchivedDataStore()
        XCTAssertEqual(reloadedEvents.events.map(\.id), ["p1"])
        XCTAssertEqual(reloadedEvents.events.first?.mode, .menopause)
        XCTAssertEqual(reloadedArchive.archivedBlocks.map(\.id.uuidString), [idC])
        XCTAssertEqual(AppSettings().phaseColor1, "#ABCDEF")

        let more = BackupPayload(
            events: [Event(id: "p2", eventType: .menstrual, date: base.addingTimeInterval(9 * day), note: "")],
            archivedBlocks: [block(idA, daysAfter: 70)],
            settings: backupSettings()
        )
        _ = BackupService.restore(more, mode: .merge, events: reloadedEvents, archived: reloadedArchive, settings: settings)
        XCTAssertEqual(Set(EventStore().events.map(\.id)), ["p1", "p2"])
        XCTAssertEqual(ArchivedDataStore().archivedBlocks.map(\.id.uuidString), [idA, idC])
    }

    func testFailedOpenLeavesStoresUntouched() throws {
        seedExisting()
        let eventsBefore = try encoded(events.events)
        let blocksBefore = try encoded(archived.archivedBlocks)
        let persistedEvents = AppGroup.defaults.data(forKey: PersistenceKeys.events)
        let persistedBlocks = AppGroup.defaults.data(forKey: PersistenceKeys.archivedData)
        let settingsBefore = settings.settingsSnapshot()

        let payload = BackupPayload(
            events: [Event(id: "z1", eventType: .menstrual, date: base.addingTimeInterval(90 * day), note: "")],
            archivedBlocks: [block(idC, daysAfter: 1)],
            settings: backupSettings(color: "#000000")
        )
        let file = try BackupFile.make(payload, appVersion: "2.0", passphrase: "right", iterations: 1_000)

        XCTAssertThrowsError(try {
            let opened = try BackupFile.open(file, passphrase: "wrong")
            _ = BackupService.restore(opened, mode: .replace, events: self.events, archived: self.archived, settings: self.settings)
        }()) { error in
            XCTAssertEqual(error as? BackupFileError, .wrongPassphrase)
        }

        XCTAssertEqual(try encoded(events.events), eventsBefore)
        XCTAssertEqual(try encoded(archived.archivedBlocks), blocksBefore)
        XCTAssertEqual(AppGroup.defaults.data(forKey: PersistenceKeys.events), persistedEvents)
        XCTAssertEqual(AppGroup.defaults.data(forKey: PersistenceKeys.archivedData), persistedBlocks)
        XCTAssertEqual(settings.settingsSnapshot(), settingsBefore)
    }

    // MARK: - Preview

    func testPreviewCountsAndRange() {
        let archivedEvent = Event(id: "a1", eventType: .menstrual, date: base.addingTimeInterval(-10 * day), note: "")
        let payload = BackupPayload(
            events: [
                Event(id: "e1", eventType: .follicular, date: base.addingTimeInterval(3 * day), note: ""),
                Event(id: "e2", eventType: .menstrual, date: base, note: ""),
                Event(id: "e3", eventType: .luteal, date: base.addingTimeInterval(25 * day), note: "")
            ],
            archivedBlocks: [block(idA, daysAfter: 1, events: [archivedEvent]), block(idB, daysAfter: 2)],
            settings: backupSettings()
        )

        let preview = BackupService.preview(payload)

        XCTAssertEqual(preview, BackupPreview(
            cycleCount: 2,
            eventCount: 3,
            earliest: base.addingTimeInterval(-10 * day),
            latest: base.addingTimeInterval(25 * day)
        ))
        let empty = BackupService.preview(BackupPayload(events: [], archivedBlocks: [], settings: backupSettings()))
        XCTAssertEqual(empty, BackupPreview(cycleCount: 0, eventCount: 0, earliest: nil, latest: nil))
    }
}
