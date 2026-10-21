import XCTest
@testable import RhythmX

/// Tag intensity (light, medium, heavy) stored beside the tag string in `Event.tagIntensity`.
/// Old data has no intensity and must decode and encode exactly as before.
@MainActor
final class TagIntensityTests: XCTestCase {

    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20))!
    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: today)! }

    override func setUp() {
        super.setUp()
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.archivedData)
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.events)
    }

    override func tearDown() {
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.archivedData)
        AppGroup.defaults.removeObject(forKey: PersistenceKeys.events)
        super.tearDown()
    }

    // MARK: - Storage contract

    func testLegacy19EventJSONDecodesWithNilIntensity() throws {
        let json = #"{"id":"E1","eventType":"menstrual","date":780000000.5,"note":"n","tags":"Mood:Tired, Cramps"}"#
        let event = try JSONDecoder().decode(Event.self, from: Data(json.utf8))
        XCTAssertNil(event.tagIntensity)
        XCTAssertEqual(event.tags, "Mood:Tired, Cramps")
    }

    func testV20EventJSONWithModeDecodesWithNilIntensity() throws {
        let json = #"{"id":"E2","eventType":"follicular","date":780000000,"note":"","tags":"Menopause:Hot Flashes","mode":"menopause"}"#
        let event = try JSONDecoder().decode(Event.self, from: Data(json.utf8))
        XCTAssertNil(event.tagIntensity)
        XCTAssertEqual(event.mode, .menopause)
    }

    func testNilIntensityEncodesWithNoKey() throws {
        let event = Event(id: "X", eventType: .luteal, date: Date(timeIntervalSinceReferenceDate: 1), note: "", tags: "Symptom:Cramps")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        XCTAssertNil(object["tagIntensity"])
        XCTAssertNil(object["mode"], "a nil mode is still omitted")
        XCTAssertEqual(Set(object.keys), ["id", "eventType", "date", "note", "tags"], "the 1.9.x shape, key for key")
    }

    func testEmptyIntensityEncodesWithNoKey() throws {
        var event = Event(id: "X", eventType: .luteal, date: Date(timeIntervalSinceReferenceDate: 1), note: "", tags: "Symptom:Cramps")
        event.tagIntensity = [:]
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        XCTAssertNil(object["tagIntensity"])
    }

    func testIntensityRoundTrips() throws {
        let event = Event(id: "X", eventType: .menstrual, date: Date(timeIntervalSinceReferenceDate: 1), note: "",
                          tags: "Symptom:Cramps, Mood:Calm", mode: .planning, tagIntensity: ["Symptom:Cramps": 3])
        let back = try JSONDecoder().decode(Event.self, from: JSONEncoder().encode(event))
        XCTAssertEqual(back.tagIntensity, ["Symptom:Cramps": 3])
        XCTAssertEqual(back.intensity(for: "Symptom:Cramps"), .heavy)
        XCTAssertNil(back.intensity(for: "Mood:Calm"))
        XCTAssertEqual(back.mode, .planning)
    }

    func testOutOfRangeOrMalformedIntensityNeverFailsTheArray() throws {
        let good = #"{"id":"A","eventType":"menstrual","date":1,"note":"","tags":"Symptom:Cramps","tagIntensity":{"Symptom:Cramps":2,"Symptom:Bloating":7,"Symptom:Headache":0}}"#
        let bad = #"{"id":"B","eventType":"menstrual","date":2,"note":"","tags":"Symptom:Cramps","tagIntensity":"heavy"}"#
        let events = try JSONDecoder().decode([Event].self, from: Data("[\(good),\(bad)]".utf8))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].tagIntensity, ["Symptom:Cramps": 2], "levels outside 1 to 3 are dropped")
        XCTAssertNil(events[1].tagIntensity)
    }

    func testBackupRoundTripKeepsIntensity() throws {
        let event = Event(id: "e1", eventType: .menstrual, date: day(0), note: "", tags: "Symptom:Cramps",
                          tagIntensity: ["Symptom:Cramps": 2])
        let block = ArchivedDataBlock(date: day(1), groupedEvents: [.init(eventType: .menstrual, events: [event])])
        let settings = AppSettings().settingsSnapshot()
        let data = try BackupFile.make(BackupPayload(events: [event], archivedBlocks: [block], settings: settings),
                                       appVersion: "2.0.0", passphrase: nil)
        let restored = try BackupFile.open(data, passphrase: nil)
        XCTAssertEqual(restored.events[0].tagIntensity, ["Symptom:Cramps": 2])
        XCTAssertEqual(restored.archivedBlocks[0].groupedEvents[0].events[0].tagIntensity, ["Symptom:Cramps": 2])
    }

    // MARK: - Logging

    private func storeWithDay() -> EventStore {
        let store = EventStore(preview: true)
        store.add(Event(id: "d", eventType: .menstrual, date: day(0), note: ""))
        return store
    }

    func testLogTagWithIntensityStoresTheLevel() {
        let store = storeWithDay()
        XCTAssertTrue(store.logTag("Symptom:Cramps", on: day(0), mode: .cycle, intensity: .medium))
        XCTAssertEqual(store.events[0].tags, "Symptom:Cramps")
        XCTAssertEqual(store.events[0].tagIntensity, ["Symptom:Cramps": 2])
    }

    func testLogTagWithoutIntensityStoresNone() {
        let store = storeWithDay()
        XCTAssertTrue(store.logTag("Symptom:Cramps", on: day(0), mode: .cycle))
        XCTAssertNil(store.events[0].tagIntensity)
    }

    func testRelogAtANewLevelUpdatesTheLevelInsteadOfDuplicating() {
        let store = storeWithDay()
        store.logTag("Symptom:Cramps", on: day(0), mode: .cycle, intensity: .light)
        XCTAssertTrue(store.logTag("Symptom:Cramps", on: day(0), mode: .cycle, intensity: .heavy))
        XCTAssertEqual(store.events[0].tags, "Symptom:Cramps", "the tag is still there once")
        XCTAssertEqual(store.events[0].intensity(for: "Symptom:Cramps"), .heavy)
    }

    func testRelogAtTheSameLevelIsADuplicate() {
        let store = storeWithDay()
        store.logTag("Symptom:Cramps", on: day(0), mode: .cycle, intensity: .medium)
        XCTAssertFalse(store.logTag("Symptom:Cramps", on: day(0), mode: .cycle, intensity: .medium))
        XCTAssertEqual(store.events[0].intensity(for: "Symptom:Cramps"), .medium)
    }

    func testRelogWithoutALevelTurnsTheLevelOffAndKeepsTheTag() {
        let store = storeWithDay()
        store.logTag("Symptom:Cramps", on: day(0), mode: .cycle, intensity: .medium)
        XCTAssertTrue(store.logTag("Symptom:Cramps", on: day(0), mode: .cycle), "no level now: the level goes back to off")
        XCTAssertEqual(store.events[0].tags, "Symptom:Cramps", "the tag stays, once")
        XCTAssertNil(store.events[0].intensity(for: "Symptom:Cramps"))
        XCTAssertNil(store.events[0].tagIntensity)
        XCTAssertFalse(store.logTag("Symptom:Cramps", on: day(0), mode: .cycle), "no level again is a duplicate")
    }

    func testTagFormDoesNotBlockTurningALevelOff() {
        let item = TagSelection.Item(pick: TagFormLogic.pick(fromRaw: "Symptom:Cramps"), count: 1, intensity: nil)
        let blocked = TagFormLogic.blockedDuplicates([item], isDuplicate: { _ in true }, storedLevel: { _ in .medium })
        XCTAssertTrue(blocked.isEmpty, "a stored level turned off is a change, not a duplicate")
        let same = TagFormLogic.blockedDuplicates([item], isDuplicate: { _ in true }, storedLevel: { _ in nil })
        XCTAssertEqual(same.count, 1, "no level on a tag with no level is still a duplicate")
    }

    func testRepeatableTagWithIntensityAppendsAndKeepsTheHigherLevel() {
        let store = EventStore(preview: true)
        XCTAssertTrue(store.logTag("Menopause:Hot Flashes", on: day(0), mode: .menopause, intensity: .heavy))
        XCTAssertTrue(store.logTag("Menopause:Hot Flashes", on: day(0), mode: .menopause, intensity: .light))
        let carrier = store.menopauseEvents[0]
        XCTAssertEqual(TagParser.split(carrier.tags).count, 2, "each hot flash still counts")
        XCTAssertEqual(carrier.intensity(for: "Menopause:Hot Flashes"), .heavy)
    }

    func testClearingRemovesTheTagAndItsIntensity() {
        let store = storeWithDay()
        store.logTag("Symptom:Cramps", on: day(0), mode: .cycle, intensity: .heavy)
        store.logTag("Mood:Calm", on: day(0), mode: .cycle, intensity: .light)
        XCTAssertTrue(store.clearTag("Symptom:Cramps", on: day(0)))
        XCTAssertEqual(store.events[0].tags, "Mood:Calm")
        XCTAssertEqual(store.events[0].tagIntensity, ["Mood:Calm": 1])
        XCTAssertFalse(store.clearTag("Symptom:Cramps", on: day(0)), "nothing left to clear")
    }

    func testClearingTheLastLevelLeavesNoEmptyMap() {
        let store = storeWithDay()
        store.logTag("Symptom:Cramps", on: day(0), mode: .cycle, intensity: .heavy)
        store.clearTag("Symptom:Cramps", on: day(0))
        XCTAssertNil(store.events[0].tagIntensity)
    }

    func testRemoveTagInPhaseDropsItsIntensity() {
        let store = storeWithDay()
        store.logTag("Symptom:Cramps", on: day(0), mode: .cycle, intensity: .heavy)
        store.removeTag("Symptom:Cramps", in: .menstrual)
        XCTAssertEqual(store.events[0].tags, "")
        XCTAssertNil(store.events[0].tagIntensity)
    }

    func testEditingTagsByUpdateDropsOrphanedIntensity() {
        let store = storeWithDay()
        store.logTag("Symptom:Cramps", on: day(0), mode: .cycle, intensity: .heavy)
        var edited = store.events[0]
        edited.tags = "Mood:Calm"
        store.update(edited)
        XCTAssertNil(store.events[0].tagIntensity)
    }

    // MARK: - Merge, restore, archive, widget

    func testMergedIntensityKeepsTheHigherLevel() {
        XCTAssertEqual(Event.mergedIntensity(["A:x": 1, "B:y": 3], ["A:x": 2, "C:z": 1]), ["A:x": 2, "B:y": 3, "C:z": 1])
        XCTAssertNil(Event.mergedIntensity(nil, nil))
        XCTAssertNil(Event.mergedIntensity([:], nil))
    }

    func testMergeKeepsTheHigherIntensity() {
        let store = EventStore(preview: true)
        store.replaceAll([Event(id: "d", eventType: .menstrual, date: day(0), note: "", tags: "Symptom:Cramps, Mood:Calm",
                                tagIntensity: ["Symptom:Cramps": 1, "Mood:Calm": 3])])
        let incoming = Event(id: "d", eventType: .menstrual, date: day(0), note: "", tags: "Symptom:Cramps, Mood:Calm",
                             tagIntensity: ["Symptom:Cramps": 3, "Mood:Calm": 1])
        let counts = store.merge([incoming])
        XCTAssertEqual(counts, EventStore.MergeCounts(added: 0, updated: 1), "a higher level counts as an update")
        XCTAssertEqual(store.events[0].tags, "Symptom:Cramps, Mood:Calm")
        XCTAssertEqual(store.events[0].tagIntensity, ["Symptom:Cramps": 3, "Mood:Calm": 3])
        XCTAssertEqual(store.merge([incoming]), EventStore.MergeCounts(added: 0, updated: 0), "merging again changes nothing")
    }

    func testMergeOfANewTagBringsItsIntensity() {
        let store = EventStore(preview: true)
        store.replaceAll([Event(id: "d", eventType: .menstrual, date: day(0), note: "")])
        store.merge([Event(id: "other", eventType: .menstrual, date: day(0), note: "", tags: "Symptom:Cramps",
                           tagIntensity: ["Symptom:Cramps": 2])])
        XCTAssertEqual(store.events.count, 1, "same day and type joins the phone's event")
        XCTAssertEqual(store.events[0].tagIntensity, ["Symptom:Cramps": 2])
    }

    func testArchiveKeepsIntensity() throws {
        let events = EventStore(preview: true)
        events.add(Event(id: "d", eventType: .menstrual, date: day(0), note: "", tags: "Symptom:Cramps",
                         tagIntensity: ["Symptom:Cramps": 3]))
        let archive = ArchivedDataStore()
        let block = try XCTUnwrap(archive.archiveCurrent(events: events.events, mode: .cycle))
        XCTAssertEqual(block.groupedEvents[0].events[0].tagIntensity, ["Symptom:Cramps": 3])
        let reloaded = ArchivedDataStore()
        XCTAssertEqual(reloaded.archivedBlocks.first?.groupedEvents.first?.events.first?.tagIntensity, ["Symptom:Cramps": 3])
    }

    func testEditingAnArchivedEventsTagsDropsOrphanedIntensity() throws {
        let archive = ArchivedDataStore()
        let event = Event(id: "d", eventType: .menstrual, date: day(0), note: "", tags: "Symptom:Cramps, Mood:Calm",
                          tagIntensity: ["Symptom:Cramps": 3, "Mood:Calm": 1])
        archive.archiveCurrent(events: [event], mode: .cycle)
        archive.updateArchivedEventTag(eventId: "d", newTags: "Mood:Calm")
        XCTAssertEqual(archive.archivedBlocks[0].groupedEvents[0].events[0].tagIntensity, ["Mood:Calm": 1])
    }

    func testQuickLogWriterKeepsExistingIntensityAndAddsNone() {
        var events = [Event(id: "d", eventType: .menstrual, date: day(0), note: "", tags: "Symptom:Bloating",
                            tagIntensity: ["Symptom:Bloating": 2])]
        XCTAssertTrue(QuickLogWriter.append(category: .symptom, value: "Cramps", to: &events, on: day(0), mode: .cycle))
        XCTAssertEqual(events[0].tags, "Symptom:Bloating, Symptom:Cramps")
        XCTAssertEqual(events[0].tagIntensity, ["Symptom:Bloating": 2])
    }

    func testQuickLogSharedStoreRoundTripKeepsIntensity() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TagIntensityTests.quicklog"))
        defaults.removePersistentDomain(forName: "TagIntensityTests.quicklog")
        defer { defaults.removePersistentDomain(forName: "TagIntensityTests.quicklog") }
        defaults.set(TrackingMode.cycle.rawValue, forKey: "trackingMode")
        let stored = [Event(id: "d", eventType: .menstrual, date: day(0), note: "", tags: "Symptom:Bloating",
                            tagIntensity: ["Symptom:Bloating": 3])]
        defaults.set(try JSONEncoder().encode(stored), forKey: PersistenceKeys.events)
        XCTAssertTrue(QuickLogWriter.log(category: .symptom, value: "Cramps", defaults: defaults, now: day(0)))
        let back = try JSONDecoder().decode([Event].self, from: try XCTUnwrap(defaults.data(forKey: PersistenceKeys.events)))
        XCTAssertEqual(back[0].tagIntensity, ["Symptom:Bloating": 3])
    }

    // MARK: - Patterns and export ignore intensity

    func testPatternCountsDoNotChangeWithIntensity() {
        let plain = (0..<3).map { Event(id: "p\($0)", eventType: .menstrual, date: day($0), note: "", tags: "Symptom:Cramps") }
        var heavy = plain
        for i in heavy.indices { heavy[i].tagIntensity = ["Symptom:Cramps": 3] }
        XCTAssertEqual(PatternFinder.heatmap(events: plain, archivedBlocks: [], mode: .cycle),
                       PatternFinder.heatmap(events: heavy, archivedBlocks: [], mode: .cycle))
    }

    func testAverageIntensityOverLevelledOccurrencesOnly() {
        let events = [
            Event(id: "a", eventType: .menstrual, date: day(0), note: "", tags: "Symptom:Cramps", tagIntensity: ["Symptom:Cramps": 1]),
            Event(id: "b", eventType: .menstrual, date: day(1), note: "", tags: "Symptom:Cramps", tagIntensity: ["Symptom:Cramps": 3]),
            Event(id: "c", eventType: .menstrual, date: day(2), note: "", tags: "Symptom:Cramps"),
            Event(id: "m", eventType: .follicular, date: day(1), note: "", tags: "Symptom:Cramps",
                  mode: .menopause, tagIntensity: ["Symptom:Cramps": 1])
        ]
        let avg = PatternFinder.averageIntensity(tag: "Symptom:Cramps", events: events, archivedBlocks: [], mode: .cycle, today: day(2))
        XCTAssertEqual(try XCTUnwrap(avg), 2.0, accuracy: 0.001, "menopause data and unlevelled logs are left out")
        XCTAssertNil(PatternFinder.averageIntensity(tag: "Mood:Calm", events: events, archivedBlocks: [], mode: .cycle, today: day(2)))
        XCTAssertEqual(try XCTUnwrap(PatternFinder.averageIntensity(tag: "Symptom:Cramps", events: events, archivedBlocks: [],
                                                                     mode: .menopause, today: day(2))), 1.0, accuracy: 0.001)
    }

    func testICSExportIsUnchangedByIntensity() {
        let plain = [Event(id: "a", eventType: .menstrual, date: day(0), note: "", tags: "Symptom:Cramps")]
        var levelled = plain
        levelled[0].tagIntensity = ["Symptom:Cramps": 3]
        XCTAssertEqual(ICSExporter.export(events: plain, sharerName: ""), ICSExporter.export(events: levelled, sharerName: ""))
    }

    // MARK: - Tag form state machine

    func testTapLevelSetsAndTapSameLevelClears() {
        XCTAssertEqual(TagFormLogic.tappedIntensity(current: nil, tapped: .medium), .medium)
        XCTAssertEqual(TagFormLogic.tappedIntensity(current: .light, tapped: .heavy), .heavy)
        XCTAssertNil(TagFormLogic.tappedIntensity(current: .heavy, tapped: .heavy))
    }

    func testSelectionTapLevelHoldsPickAtThatLevel() {
        let cramps = TagPick(category: .symptom, value: "Cramps")
        var selection = TagSelection()
        selection.tap(cramps, level: .light)
        XCTAssertTrue(selection.contains(cramps))
        XCTAssertEqual(selection.intensity(of: cramps), .light)
        selection.tap(cramps, level: .heavy)
        XCTAssertEqual(selection.intensity(of: cramps), .heavy)
        XCTAssertEqual(selection.totalCount, 1)
        selection.tap(cramps, level: .heavy)
        XCTAssertFalse(selection.contains(cramps), "tapping the held level clears the pick")
        XCTAssertNil(selection.intensity(of: cramps))
    }

    func testSelectionTagsToLogCarryTheirLevel() {
        let cramps = TagPick(category: .symptom, value: "Cramps")
        let calm = TagPick(category: .mood, value: "Calm")
        var selection = TagSelection()
        selection.tap(cramps, level: .medium)
        selection.add(calm)
        XCTAssertEqual(selection.rawTagsToLog, ["Symptom:Cramps", "Mood:Calm"])
        XCTAssertEqual(selection.tagsToLog.map(\.raw), ["Symptom:Cramps", "Mood:Calm"])
        XCTAssertEqual(selection.tagsToLog.map(\.intensity), [.medium, nil])
    }

    func testIntensityTitlesAndValues() {
        XCTAssertEqual(TagIntensity.allCases.map(\.rawValue), [1, 2, 3])
        XCTAssertEqual(TagIntensity.allCases.map(\.title), ["Light", "Medium", "Heavy"])
    }
}
