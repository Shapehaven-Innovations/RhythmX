import XCTest
@testable import RhythmX

/// Task 19: the pure Health mapping and the idempotent period-day write behind the Apple Health toggles.
@MainActor
final class HealthMappingTests: XCTestCase {
    private let calendar = Calendar.current
    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 1))!
    private func day(_ n: Int, hour: Int = 0) -> Date {
        calendar.date(byAdding: DateComponents(day: n, hour: hour), to: anchor)!
    }

    /// A generated 28-day cycle: menstrual days are offsets 0...4.
    private var cycle: [Event] { CycleGenerator.events(startDate: anchor, cycleLength: 28) }

    // MARK: - Flow samples

    func testFlowSamplesOnlyMenstrualCycleEvents() {
        // A second menstrual event on day 2 (a restore merge can leave one) must not produce a second sample.
        let duplicate = Event(id: "dup", eventType: .menstrual, date: day(2, hour: 9), note: "", mode: .cycle)
        let samples = HealthMapping.flowSamples(from: cycle + [duplicate], calendar: calendar)

        XCTAssertEqual(samples.count, 5, "one entry per menstrual day, never per event")
        XCTAssertEqual(samples.map(\.start), (0..<5).map { day($0) }, "oldest first, at the start of the day")
        for sample in samples {
            XCTAssertEqual(sample.start, calendar.startOfDay(for: sample.start))
            XCTAssertEqual(sample.end, calendar.date(byAdding: .day, value: 1, to: sample.start)!.addingTimeInterval(-1),
                           "a whole day, ending before the next one starts so Health shows it on one day")
        }
        XCTAssertEqual(samples.map(\.isCycleStart), [true, false, false, false, false],
                       "only the first day of a run of period days starts a cycle")
    }

    func testFlowSamplesMarkEachRunStart() {
        let later = CycleGenerator.events(startDate: day(28), cycleLength: 28)
        let samples = HealthMapping.flowSamples(from: cycle + later, calendar: calendar)

        XCTAssertEqual(samples.count, 10)
        XCTAssertEqual(samples.filter(\.isCycleStart).map(\.start), [day(0), day(28)])
    }

    func testFlowSamplesIgnoreMenopauseEvents() {
        let bleeding = Event(id: "meno", eventType: .menstrual, date: day(40), note: "", tags: "Symptom:Spotting", mode: .menopause)
        let planning = Event(id: "plan", eventType: .menstrual, date: day(60), note: "", mode: .planning)

        let samples = HealthMapping.flowSamples(from: cycle + [bleeding, planning], calendar: calendar)

        XCTAssertFalse(samples.contains { $0.start == day(40) }, "a Menopause event is never written to Health")
        XCTAssertTrue(samples.contains { $0.start == day(60) }, "Planning events are cycle data")
        XCTAssertTrue(HealthMapping.flowSamples(from: [bleeding], calendar: calendar).isEmpty)
    }

    // MARK: - Temperature and sleep

    func testTemperatureSamplesMapToPoints() {
        let samples: [(Date, Double)] = [
            (day(3, hour: 7), 97.9),
            (day(1, hour: 6), 97.4),
            (day(1, hour: 21), 98.6),   // an evening reading; the morning one is the basal value
            (day(2, hour: 6), 97.6),
        ]

        let points = HealthMapping.temperaturePoints(from: samples, calendar: calendar)

        XCTAssertEqual(points.map(\.date), [day(1), day(2), day(3)], "one point per day, oldest first, at start of day")
        XCTAssertEqual(points.map(\.value), [97.4, 97.6, 97.9])
        XCTAssertEqual(points.first?.id, day(1), "same identity as the tag-based points")
    }

    func testSleepSummarySumsPerNightEndingThatDay() {
        let samples: [(Date, Date)] = [
            (day(1, hour: 23), day(2, hour: 6)),   // 7 h, ends on day 2
            (day(2, hour: 13), day(2, hour: 14)),  // a 1 h nap, same day
            (day(2, hour: 23), day(3, hour: 7)),   // 8 h, ends on day 3
        ]

        let summary = HealthMapping.sleepSummary(from: samples, calendar: calendar)

        XCTAssertEqual(summary[day(2)], 8 * 3600)
        XCTAssertEqual(summary[day(3)], 8 * 3600)
        XCTAssertNil(summary[day(1)])
    }

    func testSleepSummaryCountsOverlappingSamplesOnce() {
        // Watch stages inside the iPhone's own estimate of the same night.
        let samples: [(Date, Date)] = [
            (day(1, hour: 23), day(2, hour: 6)),   // iPhone, 7 h
            (day(1, hour: 23), day(2, hour: 2)),   // watch core, overlaps
            (day(2, hour: 1), day(2, hour: 7)),    // watch REM, overlaps and runs 1 h longer
        ]
        let summary = HealthMapping.sleepSummary(from: samples, calendar: calendar)
        XCTAssertEqual(summary[day(2)], 8 * 3600, "the union of the night, 23:00 to 07:00")
    }

    func testSleepSummaryNestedAndAdjacentSamples() {
        let samples: [(Date, Date)] = [
            (day(1, hour: 22), day(2, hour: 6)),   // 8 h
            (day(2, hour: 1), day(2, hour: 3)),    // nested, adds nothing
            (day(2, hour: 6), day(2, hour: 7)),    // adjacent, adds 1 h
        ]
        let summary = HealthMapping.sleepSummary(from: samples, calendar: calendar)
        XCTAssertEqual(summary[day(2)], 9 * 3600)
        XCTAssertEqual(summary.count, 1)
    }

    func testSleepSummaryKeepsNightsApart() {
        let samples: [(Date, Date)] = [
            (day(2, hour: 23), day(3, hour: 6)),
            (day(1, hour: 23), day(2, hour: 6)),
            (day(1, hour: 23), day(2, hour: 5)),   // a second source for night one
            (day(3, hour: 23), day(4, hour: 5)),
        ]
        let summary = HealthMapping.sleepSummary(from: samples, calendar: calendar)
        XCTAssertEqual(summary[day(2)], 7 * 3600)
        XCTAssertEqual(summary[day(3)], 7 * 3600)
        XCTAssertEqual(summary[day(4)], 6 * 3600)
    }

    // MARK: - Writes

    private func makeSync(_ fake: FakeHealthStore) -> HealthSync {
        let suite = "test.healthsync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return HealthSync(store: fake, defaults: defaults)
    }

    func testWriteIsIdempotentForSameDay() async throws {
        let fake = FakeHealthStore()
        let sync = makeSync(fake)

        try await sync.writePeriodDays(from: cycle, archivedBlocks: [])
        XCTAssertEqual(fake.savedDays.count, 5)

        try await sync.writePeriodDays(from: cycle, archivedBlocks: [])
        XCTAssertEqual(fake.savedDays.count, 5, "a day already in Health is not written again")

        let extra = Event(id: "x", eventType: .menstrual, date: day(5), note: "", mode: .cycle)
        try await sync.writePeriodDays(from: cycle + [extra], archivedBlocks: [])
        XCTAssertEqual(fake.savedDays.count, 6, "only the new day is written")
        XCTAssertEqual(fake.savedDays.last, day(5))
    }

    func testWrittenDaysSurviveANewSyncInstance() async throws {
        let fake = FakeHealthStore()
        let suite = "test.healthsync.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        try await HealthSync(store: fake, defaults: defaults).writePeriodDays(from: cycle, archivedBlocks: [])
        try await HealthSync(store: fake, defaults: defaults).writePeriodDays(from: cycle, archivedBlocks: [])

        XCTAssertEqual(fake.savedDays.count, 5, "the written-day record lives in UserDefaults, not in memory")
    }

    func testFailedWriteIsNotRecordedAsWritten() async {
        let fake = FakeHealthStore()
        fake.failsNextSave = true
        let sync = makeSync(fake)

        do {
            try await sync.writePeriodDays(from: cycle, archivedBlocks: [])
            XCTFail("expected the save error to surface")
        } catch {}
        XCTAssertTrue(fake.savedDays.isEmpty)

        try? await sync.writePeriodDays(from: cycle, archivedBlocks: [])
        XCTAssertEqual(fake.savedDays.count, 5, "the days are retried after a failed save")
    }

    func testMenopauseEventsNeverWritten() async throws {
        let fake = FakeHealthStore()
        let sync = makeSync(fake)
        let bleeding = Event(id: "meno", eventType: .menstrual, date: day(40), note: "", mode: .menopause)

        try await sync.writePeriodDays(from: [bleeding], archivedBlocks: [])

        XCTAssertTrue(fake.savedDays.isEmpty)
    }

    // MARK: - Mirrored deletions

    private func makeSync(_ fake: FakeHealthStore, defaults: UserDefaults) -> HealthSync {
        HealthSync(store: fake, defaults: defaults)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "test.healthsync.delete.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testRemovedPeriodDaysAreDeletedFromHealth() async throws {
        let fake = FakeHealthStore()
        let sync = makeSync(fake)
        try await sync.writePeriodDays(from: cycle, archivedBlocks: [])
        XCTAssertEqual(fake.ownSampleDays, (0..<5).map { day($0) })

        // Day 4 deleted, day 3 retyped, day 2 moved to Menopause mode.
        let changed: [Event] = cycle.compactMap { e in
            if calendar.isDate(e.date, inSameDayAs: day(4)) { return nil }
            var copy = e
            if calendar.isDate(e.date, inSameDayAs: day(3)) { copy.eventType = .follicular }
            if calendar.isDate(e.date, inSameDayAs: day(2)) { copy.mode = .menopause }
            return copy
        }
        try await sync.writePeriodDays(from: changed, archivedBlocks: [])

        XCTAssertEqual(fake.ownSampleDays, [day(0), day(1)], "the days that stopped being period days left Health")
        XCTAssertEqual(fake.savedDays.count, 5, "nothing was written again")

        try await sync.writePeriodDays(from: changed, archivedBlocks: [])
        XCTAssertEqual(fake.deleteRequests.count, 1, "a removed day is deleted once")
    }

    func testDeleteOnlyTouchesSamplesRhythmXWrote() async throws {
        let fake = FakeHealthStore()
        let foreign = UUID()
        fake.samples.append(.init(id: foreign, start: day(4), isOwn: false))
        let sync = makeSync(fake)
        try await sync.writePeriodDays(from: cycle, archivedBlocks: [])
        let ownDay4 = fake.samples.first { $0.isOwn && $0.start == day(4) }!.id

        let withoutDay4 = cycle.filter { !calendar.isDate($0.date, inSameDayAs: day(4)) }
        try await sync.writePeriodDays(from: withoutDay4, archivedBlocks: [])

        XCTAssertEqual(fake.deleteRequests.flatMap { $0 }, [ownDay4],
                       "only the sample RhythmX saved is asked to be deleted")
        XCTAssertTrue(fake.samples.contains { $0.id == foreign }, "another app's sample is never touched")
    }

    func testFailedDeleteIsRetriedAndKeepsTheDayRecorded() async throws {
        let fake = FakeHealthStore()
        let defaults = freshDefaults()
        let sync = makeSync(fake, defaults: defaults)
        try await sync.writePeriodDays(from: cycle, archivedBlocks: [])
        let withoutDay4 = cycle.filter { !calendar.isDate($0.date, inSameDayAs: day(4)) }

        fake.failsNextDelete = true
        do {
            try await sync.writePeriodDays(from: withoutDay4, archivedBlocks: [])
            XCTFail("expected the delete error to surface")
        } catch {}
        XCTAssertTrue(fake.ownSampleDays.contains(day(4)))
        XCTAssertTrue(HealthSync(store: fake, defaults: defaults).writtenDayKeys.contains(FertileWindow.dayKey(day(4), calendar: calendar)),
                      "a failed delete never marks the day removed")

        try await sync.writePeriodDays(from: withoutDay4, archivedBlocks: [])
        XCTAssertFalse(fake.ownSampleDays.contains(day(4)), "the delete is retried on the next sync")
    }

    func testTurningWriteOffLeavesWrittenSamples() async throws {
        let fake = FakeHealthStore()
        let sync = makeSync(fake)
        let settings = AppSettings()
        let previous = settings.healthWritePeriod
        defer { settings.healthWritePeriod = previous }

        settings.healthWritePeriod = true
        await sync.refresh(events: cycle, archivedBlocks: [], settings: settings)
        XCTAssertEqual(fake.ownSampleDays.count, 5)

        settings.healthWritePeriod = false
        await sync.refresh(events: [], archivedBlocks: [], settings: settings)

        XCTAssertTrue(fake.deleteRequests.isEmpty, "switching off only stops writing")
        XCTAssertEqual(fake.ownSampleDays.count, 5, "history stays in Health")
    }

    func testReAddingARemovedDayWritesItAgain() async throws {
        let fake = FakeHealthStore()
        let sync = makeSync(fake)
        try await sync.writePeriodDays(from: cycle, archivedBlocks: [])
        let withoutDay4 = cycle.filter { !calendar.isDate($0.date, inSameDayAs: day(4)) }
        try await sync.writePeriodDays(from: withoutDay4, archivedBlocks: [])
        XCTAssertFalse(fake.ownSampleDays.contains(day(4)))

        try await sync.writePeriodDays(from: cycle, archivedBlocks: [])

        XCTAssertEqual(fake.ownSampleDays, (0..<5).map { day($0) })
        XCTAssertEqual(fake.savedDays.count, 6, "the day came back, so it is written once more")
    }

    func testDaysRecordedBeforeSampleIDsAreDeletedByTheirOwnDay() async throws {
        let fake = FakeHealthStore()
        let defaults = freshDefaults()
        let keys = (0..<5).map { FertileWindow.dayKey(day($0), calendar: calendar) }
        defaults.set(keys, forKey: HealthSync.writtenDaysKey)
        fake.samples = (0..<5).map { .init(id: UUID(), start: day($0), isOwn: true) }
        let sync = makeSync(fake, defaults: defaults)

        try await sync.writePeriodDays(from: cycle, archivedBlocks: [])
        XCTAssertTrue(fake.savedDays.isEmpty, "days in the older record are not written twice")

        let day4 = try XCTUnwrap(fake.samples.first { $0.start == day(4) }?.id)
        let withoutDay4 = cycle.filter { !calendar.isDate($0.date, inSameDayAs: day(4)) }
        try await sync.writePeriodDays(from: withoutDay4, archivedBlocks: [])

        let request = try XCTUnwrap(fake.deleteRequests.first)
        XCTAssertEqual(request, [day4], "no ID known, so its own sample for that day is looked up and deleted by ID")
        XCTAssertEqual(fake.ownSampleDays, (0..<4).map { day($0) })
    }

    // MARK: - Archives, cycle starts, adoption

    private func block(_ events: [Event], mode: TrackingMode? = nil) -> ArchivedDataBlock {
        let grouped = Dictionary(grouping: events, by: \.eventType).map {
            ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value)
        }
        return ArchivedDataBlock(date: events.map(\.date).max() ?? anchor, groupedEvents: grouped, mode: mode)
    }

    func testArchivingACycleKeepsItsSamples() async throws {
        let fake = FakeHealthStore()
        let sync = makeSync(fake)
        try await sync.writePeriodDays(from: cycle, archivedBlocks: [])

        // The cycle moves from the live events into an archive.
        try await sync.writePeriodDays(from: [], archivedBlocks: [block(cycle)])

        XCTAssertTrue(fake.deleteRequests.isEmpty, "archiving is not deleting")
        XCTAssertEqual(fake.ownSampleDays, (0..<5).map { day($0) })
        XCTAssertEqual(fake.savedDays.count, 5)
    }

    func testDeletingALiveDayStillRemovesItWhenArchivesExist() async throws {
        let fake = FakeHealthStore()
        let sync = makeSync(fake)
        let current = CycleGenerator.events(startDate: day(28), cycleLength: 28)
        try await sync.writePeriodDays(from: current, archivedBlocks: [block(cycle)])
        XCTAssertEqual(fake.ownSampleDays.count, 10)

        let withoutDay30 = current.filter { !calendar.isDate($0.date, inSameDayAs: day(30)) }
        try await sync.writePeriodDays(from: withoutDay30, archivedBlocks: [block(cycle)])

        XCTAssertFalse(fake.ownSampleDays.contains(day(30)))
        XCTAssertEqual(fake.ownSampleDays.count, 9, "the archived days stay")
    }

    func testArchiveMovedToMenopauseRemovesItsSamples() async throws {
        let fake = FakeHealthStore()
        let sync = makeSync(fake)
        try await sync.writePeriodDays(from: [], archivedBlocks: [block(cycle)])
        XCTAssertEqual(fake.ownSampleDays.count, 5)

        try await sync.writePeriodDays(from: [], archivedBlocks: [block(cycle, mode: .menopause)])

        XCTAssertTrue(fake.ownSampleDays.isEmpty, "Menopause archives are not period days")
    }

    func testCycleStartFlipRewritesTheDay() async throws {
        let fake = FakeHealthStore()
        let defaults = freshDefaults()
        let sync = makeSync(fake, defaults: defaults)
        let fromDay1 = cycle.filter { !calendar.isDate($0.date, inSameDayAs: day(0)) }
        try await sync.writePeriodDays(from: fromDay1, archivedBlocks: [])
        XCTAssertEqual(fake.sample(on: day(1))?.isCycleStart, true)

        // An earlier day joins the run: day 1 no longer starts the cycle.
        try await HealthSync(store: fake, defaults: defaults).writePeriodDays(from: cycle, archivedBlocks: [])
        XCTAssertEqual(fake.ownSampleDays, (0..<5).map { day($0) })
        XCTAssertEqual(fake.sample(on: day(0))?.isCycleStart, true)
        XCTAssertEqual(fake.sample(on: day(1))?.isCycleStart, false, "deleted and saved again with the new flag")
        XCTAssertEqual(fake.samples.filter { $0.start == day(1) }.count, 1)

        // The first day is deleted again: day 1 starts the cycle once more.
        try await sync.writePeriodDays(from: fromDay1, archivedBlocks: [])
        XCTAssertEqual(fake.sample(on: day(1))?.isCycleStart, true)
        XCTAssertEqual(fake.ownSampleDays, (1..<5).map { day($0) })

        // Nothing changes: nothing is rewritten.
        let saves = fake.savedDays.count
        try await sync.writePeriodDays(from: fromDay1, archivedBlocks: [])
        XCTAssertEqual(fake.savedDays.count, saves)
    }

    func testOwnSamplesFromAnEarlierInstallAreAdopted() async throws {
        let fake = FakeHealthStore()
        fake.samples = (0..<5).map { .init(id: UUID(), start: day($0), isOwn: true, isCycleStart: $0 == 0) }
        let sync = makeSync(fake)   // a fresh record, as after a reinstall or on a new device

        try await sync.writePeriodDays(from: cycle, archivedBlocks: [])

        XCTAssertTrue(fake.savedDays.isEmpty, "the samples already in Health are adopted, not saved twice")
        XCTAssertEqual(fake.samples.count, 5)
        XCTAssertEqual(sync.writtenDayKeys.count, 5)

        let day4 = fake.sample(on: day(4))!.id
        let withoutDay4 = cycle.filter { !calendar.isDate($0.date, inSameDayAs: day(4)) }
        try await sync.writePeriodDays(from: withoutDay4, archivedBlocks: [])
        XCTAssertEqual(fake.deleteRequests, [[day4]], "an adopted sample is deleted by its ID")
    }

    func testAdoptedSampleWithAnOutdatedCycleStartIsRewritten() async throws {
        let fake = FakeHealthStore()
        fake.samples = [.init(id: UUID(), start: day(1), isOwn: true, isCycleStart: true)]
        let sync = makeSync(fake)

        try await sync.writePeriodDays(from: Array(cycle.filter { $0.eventType == .menstrual }.prefix(2)), archivedBlocks: [])

        XCTAssertEqual(fake.ownSampleDays, [day(0), day(1)])
        XCTAssertEqual(fake.sample(on: day(1))?.isCycleStart, false)
    }

    func testFailedLookupSavesNothing() async {
        let fake = FakeHealthStore()
        fake.failsNextOwnQuery = true
        let sync = makeSync(fake)

        do {
            try await sync.writePeriodDays(from: cycle, archivedBlocks: [])
            XCTFail("expected the lookup error to surface")
        } catch {}
        XCTAssertTrue(fake.savedDays.isEmpty, "without the lookup a save could duplicate a sample")

        try? await sync.writePeriodDays(from: cycle, archivedBlocks: [])
        XCTAssertEqual(fake.savedDays.count, 5)
    }

    // MARK: - Deletion bookkeeping

    func testLegacyDayMatchesItsOwnSampleWithinFourteenHours() async throws {
        let fake = FakeHealthStore()
        let defaults = freshDefaults()
        let keys = (3..<5).map { FertileWindow.dayKey(day($0), calendar: calendar) }
        defaults.set(keys, forKey: HealthSync.writtenDaysKey)
        let shifted = UUID()
        let neighbor = UUID()
        let foreign = UUID()
        fake.samples = [
            .init(id: neighbor, start: day(3), isOwn: true),
            .init(id: shifted, start: day(4).addingTimeInterval(-5 * 3600), isOwn: true),   // saved in another time zone
            .init(id: foreign, start: day(4), isOwn: false),
        ]
        let sync = makeSync(fake, defaults: defaults)
        let upToDay3 = cycle.filter { $0.date < day(4) }

        try await sync.writePeriodDays(from: upToDay3, archivedBlocks: [])

        XCTAssertEqual(fake.deleteRequests, [[shifted]], "the neighbouring day and another app's sample are left alone")
        XCTAssertTrue(fake.samples.contains { $0.id == neighbor })
        XCTAssertTrue(fake.samples.contains { $0.id == foreign })
        XCTAssertFalse(sync.writtenDayKeys.contains(keys[1]))
    }

    func testSampleAlreadyRemovedInHealthDropsTheRecord() async throws {
        let fake = FakeHealthStore()
        let sync = makeSync(fake)
        try await sync.writePeriodDays(from: cycle, archivedBlocks: [])
        fake.samples.removeAll { $0.start == day(4) }   // she deleted it in the Health app

        let withoutDay4 = cycle.filter { !calendar.isDate($0.date, inSameDayAs: day(4)) }
        try await sync.writePeriodDays(from: withoutDay4, archivedBlocks: [])
        try await sync.writePeriodDays(from: withoutDay4, archivedBlocks: [])

        XCTAssertEqual(fake.deleteRequests.count, 1, "nothing left to delete, so the day is not tried again")
        XCTAssertEqual(fake.lastDeletedCount, 0)
        XCTAssertFalse(sync.writtenDayKeys.contains(FertileWindow.dayKey(day(4), calendar: calendar)))
    }

    // MARK: - Refresh

    func testOneFailingStepDoesNotSkipTheOthers() async {
        let fake = FakeHealthStore()
        fake.failsNextSave = true
        fake.temperatures = [(Date().addingTimeInterval(-3600), 97.4)]
        fake.sleep = [(Date().addingTimeInterval(-8 * 3600), Date().addingTimeInterval(-3600))]
        let sync = makeSync(fake)
        let settings = AppSettings()
        let previous = (settings.healthWritePeriod, settings.healthReadTemperature, settings.healthReadSleep)
        defer {
            settings.healthWritePeriod = previous.0
            settings.healthReadTemperature = previous.1
            settings.healthReadSleep = previous.2
        }
        settings.healthWritePeriod = true
        settings.healthReadTemperature = true
        settings.healthReadSleep = true

        await sync.refresh(events: cycle, archivedBlocks: [], settings: settings)

        XCTAssertNotNil(sync.lastError, "the failed write is reported")
        XCTAssertEqual(sync.importedTemperatures.count, 1, "temperature import still ran")
        XCTAssertEqual(sync.importedSleep.count, 1, "sleep import still ran")
    }

    // MARK: - Authorization and imports

    func testWriteNeedsSharingAuthorized() async {
        let fake = FakeHealthStore()
        fake.writeAuthorized = false
        let sync = makeSync(fake)

        let write = await sync.requestAuthorization(write: true, readTemperature: false, readSleep: false)
        let read = await sync.requestAuthorization(write: false, readTemperature: true, readSleep: false)

        XCTAssertFalse(write, "Health did not allow sharing, so the write switch turns off")
        XCTAssertTrue(read, "read access is never reported, so a completed request counts")
    }

    func testRequestAuthorizationAsksOnlyForWhatWasSwitchedOn() async {
        let fake = FakeHealthStore()
        let sync = makeSync(fake)

        let granted = await sync.requestAuthorization(write: false, readTemperature: true, readSleep: false)

        XCTAssertTrue(granted)
        XCTAssertEqual(fake.authorizationRequests.count, 1)
        XCTAssertEqual(fake.authorizationRequests.first?.write, false)
        XCTAssertEqual(fake.authorizationRequests.first?.readTemperature, true)
        XCTAssertEqual(fake.authorizationRequests.first?.readSleep, false)
    }

    func testRequestAuthorizationReturnsFalseWhenTheStoreRefuses() async {
        let fake = FakeHealthStore()
        fake.failsAuthorization = true
        let sync = makeSync(fake)

        let granted = await sync.requestAuthorization(write: true, readTemperature: false, readSleep: false)

        XCTAssertFalse(granted)
    }

    func testImportTemperaturesPublishesPointsWithoutTouchingEvents() async throws {
        let fake = FakeHealthStore()
        fake.temperatures = [(day(1, hour: 6), 97.4), (day(2, hour: 6), 97.6)]
        let sync = makeSync(fake)

        let points = try await sync.importTemperatures(since: day(0))

        XCTAssertEqual(points.map(\.value), [97.4, 97.6])
        XCTAssertEqual(sync.importedTemperatures, points, "kept for the Planning chart and the tag form note")
        XCTAssertEqual(fake.temperatureQueriesSince, [day(0)])
    }

    func testImportedTemperaturesFeedPlanningInsightsWithoutReplacingTags() {
        let tagged = cycle.map { e -> Event in
            guard calendar.isDate(e.date, inSameDayAs: day(2)) else { return e }
            var copy = e
            copy.tags = "Basal Temp:97.9"
            return copy
        }
        let imported = [PlanningInsights.TempPoint(date: day(1), value: 97.4),
                        PlanningInsights.TempPoint(date: day(2), value: 97.0)]

        let insights = PlanningInsights.make(events: tagged, overrides: FertileOverrides(), today: day(3),
                                             importedTemperatures: imported, calendar: calendar)

        XCTAssertEqual(insights.temperatures.map(\.date), [day(1), day(2)])
        XCTAssertEqual(insights.temperatures.map(\.value), [97.4, 97.9], "a logged tag wins over the Health value for the same day")
        XCTAssertEqual(tagged.filter { $0.tags.contains("97.4") }.count, 0, "nothing was copied into events")
    }

    func testImportedTemperaturesStayInsideTheCurrentCycle() {
        let next = CycleGenerator.events(startDate: day(28), cycleLength: 28)
        let imported = [PlanningInsights.TempPoint(date: day(5), value: 97.1),    // last cycle
                        PlanningInsights.TempPoint(date: day(29), value: 97.3),   // this cycle
                        PlanningInsights.TempPoint(date: day(30), value: 97.5),   // today
                        PlanningInsights.TempPoint(date: day(31), value: 97.7)]   // after today
        let tagged = next.map { e -> Event in
            guard calendar.isDate(e.date, inSameDayAs: day(29)) else { return e }
            var copy = e
            copy.tags = "Basal Temp:98.0"
            return copy
        }

        let insights = PlanningInsights.make(events: cycle + tagged, overrides: FertileOverrides(), today: day(30),
                                             importedTemperatures: imported, calendar: calendar)

        XCTAssertEqual(insights.temperatures.map(\.date), [day(29), day(30)])
        XCTAssertEqual(insights.temperatures.map(\.value), [98.0, 97.5], "a logged tag still wins for its day")
    }

    func testImportedTemperaturesEndAtTheNextCycleStart() {
        let next = CycleGenerator.events(startDate: day(28), cycleLength: 28)
        let imported = [PlanningInsights.TempPoint(date: day(27), value: 97.1),
                        PlanningInsights.TempPoint(date: day(28), value: 97.3)]

        // Today is before the later cycle starts, so the current cycle is the first one.
        let insights = PlanningInsights.make(events: cycle + next, overrides: FertileOverrides(), today: day(27),
                                             importedTemperatures: imported, calendar: calendar)

        XCTAssertEqual(insights.temperatures.map(\.date), [day(27)])
    }

    func testHealthTemperatureNoteForDay() {
        let sync = makeSync(FakeHealthStore())
        sync.importedTemperatures = [PlanningInsights.TempPoint(date: day(4), value: 97.8)]

        XCTAssertEqual(sync.temperature(on: day(4, hour: 15)), 97.8)
        XCTAssertNil(sync.temperature(on: day(5)))
    }
}

// MARK: - Fake store

@MainActor
final class FakeHealthStore: HealthStoring {
    struct AuthorizationRequest { let write: Bool; let readTemperature: Bool; let readSleep: Bool }
    struct Failure: Error {}
    /// A flow sample in the fake Health database; `isOwn` is false for samples another app wrote.
    struct Sample: Equatable {
        let id: UUID
        let start: Date
        let isOwn: Bool
        var isCycleStart: Bool? = nil
    }

    var isAvailable: Bool = true
    var writeAuthorized = true
    var failsAuthorization = false
    var failsNextSave = false
    var failsNextDelete = false
    var failsNextOwnQuery = false
    var authorizationRequests: [AuthorizationRequest] = []
    var savedDays: [Date] = []
    var samples: [Sample] = []
    var deleteRequests: [Set<UUID>] = []
    var lastDeletedCount: Int?
    var temperatures: [(Date, Double)] = []
    var sleep: [(Date, Date)] = []
    var temperatureQueriesSince: [Date] = []

    var ownSampleDays: [Date] { samples.filter(\.isOwn).map(\.start).sorted() }
    func sample(on day: Date) -> Sample? { samples.first { $0.isOwn && $0.start == day } }

    var canWriteFlow: Bool { writeAuthorized }

    func requestAuthorization(write: Bool, readTemperature: Bool, readSleep: Bool) async throws {
        authorizationRequests.append(AuthorizationRequest(write: write, readTemperature: readTemperature, readSleep: readSleep))
        if failsAuthorization { throw Failure() }
    }

    func saveFlowDays(_ days: [HealthMapping.FlowDay]) async throws -> [String: UUID] {
        if failsNextSave {
            failsNextSave = false
            throw Failure()
        }
        savedDays.append(contentsOf: days.map(\.start))
        var ids: [String: UUID] = [:]
        for day in days {
            let id = UUID()
            samples.append(Sample(id: id, start: day.start, isOwn: true, isCycleStart: day.isCycleStart))
            ids[day.dayKey] = id
        }
        return ids
    }

    /// Like HealthKit with the own-source predicate: this app's samples that start in `start..<end`.
    func ownFlowSamples(start: Date, end: Date) async throws -> [HealthMapping.OwnFlowSample] {
        if failsNextOwnQuery {
            failsNextOwnQuery = false
            throw Failure()
        }
        return samples.filter { $0.isOwn && $0.start >= start && $0.start < end }
            .map { HealthMapping.OwnFlowSample(id: $0.id, start: $0.start, isCycleStart: $0.isCycleStart) }
    }

    /// Like HealthKit: only this app's samples can go.
    func deleteFlowSamples(ids: Set<UUID>) async throws -> Int {
        if failsNextDelete {
            failsNextDelete = false
            throw Failure()
        }
        deleteRequests.append(ids)
        let before = samples.count
        samples.removeAll { $0.isOwn && ids.contains($0.id) }
        lastDeletedCount = before - samples.count
        return before - samples.count
    }

    func temperatureSamples(since: Date) async throws -> [(Date, Double)] {
        temperatureQueriesSince.append(since)
        return temperatures
    }

    func sleepSamples(since: Date) async throws -> [(Date, Date)] { sleep }
}
