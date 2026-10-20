//  HealthSync.swift
//  Apple Health, opt in per type. Writes period days as menstrual flow; reads basal temperature and sleep
//  for the Planning chart, the tag form note and the Menopause view. Everything stays on the device: the
//  real store is HKHealthStore behind `HealthStoring`, so the mapping and the write bookkeeping are testable
//  with a fake. Imported values are never copied into events.

import Foundation
import Combine
import HealthKit

// MARK: - Pure mapping

enum HealthMapping {
    /// One period day for Health: the whole local day, flagged when it opens a run of period days
    /// (Health requires the cycle-start flag on every menstrual flow sample).
    struct FlowDay: Equatable {
        let start: Date
        let end: Date
        let isCycleStart: Bool
        /// "yyyy-MM-dd" of the day, the key the written-day record uses.
        let dayKey: String
    }

    /// A menstrual flow sample this app saved, as Health returns it (possibly from an earlier install).
    /// `isCycleStart` is nil when the sample carries no cycle-start flag.
    struct OwnFlowSample: Equatable {
        let id: UUID
        let start: Date
        let isCycleStart: Bool?
    }

    /// How far a sample's start may sit from local midnight and still belong to that day: a sample saved in
    /// another time zone starts up to 14 hours away.
    static let dayMatchWindow: TimeInterval = 14 * 3600

    /// The day start in `dayStarts` nearest to `date`, when it is within `dayMatchWindow`.
    static func nearestDay(to date: Date, in dayStarts: [Date]) -> Date? {
        let best = dayStarts.min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }
        guard let best, abs(best.timeIntervalSince(date)) < dayMatchWindow else { return nil }
        return best
    }

    /// The whole local day a "yyyy-MM-dd" key names.
    static func dayRange(forKey key: String, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, next.addingTimeInterval(-1))
    }

    /// Menstrual-phase days of cycle data (Menopause events never count), one entry per day however many
    /// events share it, oldest first. The first day of each run of consecutive days is a cycle start.
    /// The period days Health should hold: live events plus the menstrual days of every archived cycle (an
    /// archive is not a deletion). Menopause archives and Menopause events never count.
    static func flowSamples(from events: [Event], archivedBlocks: [ArchivedDataBlock],
                            calendar: Calendar = .current) -> [FlowDay] {
        let archived = archivedBlocks
            .filter { $0.effectiveMode != .menopause }
            .flatMap { $0.groupedEvents.flatMap(\.events) }
        return flowSamples(from: events + archived, calendar: calendar)
    }

    static func flowSamples(from events: [Event], calendar: Calendar = .current) -> [FlowDay] {
        let days = Set(events
            .filter { $0.eventType == .menstrual && $0.effectiveMode != .menopause }
            .map { calendar.startOfDay(for: $0.date) })
        return days.sorted().compactMap { day in
            guard let next = calendar.date(byAdding: .day, value: 1, to: day),
                  let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
            return FlowDay(start: day,
                           end: next.addingTimeInterval(-1),
                           isCycleStart: !days.contains(previous),
                           dayKey: FertileWindow.dayKey(day, calendar: calendar))
        }
    }

    /// One point per day at the start of that day, oldest first. With several readings on a day the earliest
    /// is kept: basal temperature is the waking reading.
    static func temperaturePoints(from samples: [(Date, Double)], calendar: Calendar = .current) -> [PlanningInsights.TempPoint] {
        var earliest: [Date: (Date, Double)] = [:]
        for (date, value) in samples {
            let day = calendar.startOfDay(for: date)
            if let current = earliest[day], current.0 <= date { continue }
            earliest[day] = (date, value)
        }
        return earliest.keys.sorted().map { PlanningInsights.TempPoint(date: $0, value: earliest[$0]!.1) }
    }

    /// Seconds asleep per day, where a stretch of sleep belongs to the day it ends on (the morning after).
    /// Samples from several sources (watch stages and the iPhone's estimate) overlap, so their union is
    /// counted: overlapping, nested and touching samples merge into one stretch before it is summed.
    static func sleepSummary(from samples: [(Date, Date)], calendar: Calendar = .current) -> [Date: TimeInterval] {
        var merged: [(start: Date, end: Date)] = []
        for (start, end) in samples.filter({ $0.1 > $0.0 }).sorted(by: { $0.0 < $1.0 }) {
            if let last = merged.last, start <= last.end {
                merged[merged.count - 1].end = max(last.end, end)
            } else {
                merged.append((start, end))
            }
        }
        var result: [Date: TimeInterval] = [:]
        for stretch in merged {
            result[calendar.startOfDay(for: stretch.end), default: 0] += stretch.end.timeIntervalSince(stretch.start)
        }
        return result
    }
}

// MARK: - Store protocol

/// The part of HealthKit the app uses. `HealthKitStore` is the real one; tests inject a fake.
@MainActor
protocol HealthStoring: AnyObject {
    var isAvailable: Bool { get }
    /// Whether Health allows writing menstrual flow (`.sharingAuthorized`). Read access is never reported.
    var canWriteFlow: Bool { get }
    /// Asks only for the types that are true. Read access is never reported back by Health, so a completed
    /// request counts as granted; a thrown error means the prompt could not be shown.
    func requestAuthorization(write: Bool, readTemperature: Bool, readSleep: Bool) async throws
    /// Saves one sample per day and returns each day key's sample ID.
    func saveFlowDays(_ days: [HealthMapping.FlowDay]) async throws -> [String: UUID]
    /// This app's own flow samples (any install, any device) that start in `start..<end`.
    func ownFlowSamples(start: Date, end: Date) async throws -> [HealthMapping.OwnFlowSample]
    /// Deletes these flow samples when this app wrote them, never another app's (HealthKit allows only that
    /// anyway). Returns how many were deleted.
    func deleteFlowSamples(ids: Set<UUID>) async throws -> Int
    func temperatureSamples(since: Date) async throws -> [(Date, Double)]
    /// Asleep stretches (not "in bed") as (start, end).
    func sleepSamples(since: Date) async throws -> [(Date, Date)]
}

@MainActor
final class HealthKitStore: HealthStoring {
    private let store = HKHealthStore()
    private static let flowType = HKCategoryType(.menstrualFlow)
    private static let temperatureType = HKQuantityType(.basalBodyTemperature)
    private static let sleepType = HKCategoryType(.sleepAnalysis)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var canWriteFlow: Bool { store.authorizationStatus(for: Self.flowType) == .sharingAuthorized }

    /// Readings come back in the unit the user's region uses, the same one she types into Basal Temp tags.
    static var temperatureUnit: HKUnit {
        Locale.current.measurementSystem == .us ? .degreeFahrenheit() : .degreeCelsius()
    }

    func requestAuthorization(write: Bool, readTemperature: Bool, readSleep: Bool) async throws {
        var share = Set<HKSampleType>()
        var read = Set<HKObjectType>()
        if write { share.insert(Self.flowType) }
        if readTemperature { read.insert(Self.temperatureType) }
        if readSleep { read.insert(Self.sleepType) }
        guard !share.isEmpty || !read.isEmpty else { return }
        try await store.requestAuthorization(toShare: share, read: read)
    }

    func saveFlowDays(_ days: [HealthMapping.FlowDay]) async throws -> [String: UUID] {
        guard !days.isEmpty else { return [:] }
        // The app records no flow intensity, so every day is "unspecified".
        let samples = days.map { day in
            (day.dayKey, HKCategorySample(type: Self.flowType,
                                          value: HKCategoryValueVaginalBleeding.unspecified.rawValue,
                                          start: day.start, end: day.end,
                                          metadata: [HKMetadataKeyMenstrualCycleStart: day.isCycleStart]))
        }
        try await store.save(samples.map(\.1))
        return Dictionary(samples.map { ($0.0, $0.1.uuid) }, uniquingKeysWith: { first, _ in first })
    }

    func ownFlowSamples(start: Date, end: Date) async throws -> [HealthMapping.OwnFlowSample] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
        ])
        return try await samples(of: Self.flowType, predicate: predicate).map { sample in
            let flag = sample.metadata?[HKMetadataKeyMenstrualCycleStart]
            return HealthMapping.OwnFlowSample(id: sample.uuid, start: sample.startDate,
                                               isCycleStart: (flag as? NSNumber)?.boolValue ?? (flag as? Bool))
        }
    }

    func deleteFlowSamples(ids: Set<UUID>) async throws -> Int {
        guard !ids.isEmpty else { return 0 }
        // Restricted to this app's own samples, so a flow day another app logged is never touched.
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(with: ids),
        ])
        return try await store.deleteObjects(of: Self.flowType, predicate: predicate)
    }

    func temperatureSamples(since: Date) async throws -> [(Date, Double)] {
        let unit = Self.temperatureUnit
        return try await samples(of: Self.temperatureType, since: since)
            .compactMap { $0 as? HKQuantitySample }
            .map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    func sleepSamples(since: Date) async throws -> [(Date, Date)] {
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        return try await samples(of: Self.sleepType, since: since)
            .compactMap { $0 as? HKCategorySample }
            .filter { asleep.contains($0.value) }
            .map { ($0.startDate, $0.endDate) }
    }

    private func samples(of type: HKSampleType, since: Date) async throws -> [HKSample] {
        try await samples(of: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil, options: []))
    }

    private func samples(of type: HKSampleType, predicate: NSPredicate) async throws -> [HKSample] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sort]) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }
}

// MARK: - Sync

@MainActor
final class HealthSync: ObservableObject {
    /// Day keys written to Health before sample IDs were kept. Read once and folded into `writtenRecordsKey`.
    static let writtenDaysKey = "healthWrittenFlowDays"
    /// Day key to the IDs of the samples RhythmX saved for it, before the cycle-start flag was kept. Read once
    /// and folded into `writtenRecordsKey`.
    static let writtenSamplesKey = "healthWrittenFlowSamples"
    /// Day key to the samples RhythmX saved (or adopted) for that day and the cycle-start flag they carry, so a
    /// day is written once however often the events change, rewritten when its flag changes, and deleted again
    /// when it stops being a period day.
    static let writtenRecordsKey = "healthWrittenFlowRecords"
    /// How far back temperature and sleep are read.
    static let importWindowDays = 365

    struct WrittenDay: Codable, Equatable {
        var ids: [String]
        /// Nil for days recorded before the flag was kept; filled in with the current value on the next sync.
        var isCycleStart: Bool?
    }

    /// Basal temperatures read from Health, one per day. Shown on the Planning chart and offered in the tag
    /// form; never added to events.
    @Published var importedTemperatures: [PlanningInsights.TempPoint] = []
    /// Seconds asleep per day, from Health.
    @Published var importedSleep: [Date: TimeInterval] = [:]
    @Published private(set) var lastError: String?

    private let store: HealthStoring
    private let defaults: UserDefaults
    private let calendar: Calendar
    private var cancellables = Set<AnyCancellable>()
    /// The write in progress; the next one waits for it so a day is never saved or deleted twice.
    private var writeTask: Task<Void, Error>?

    /// - Parameter store: nil uses HealthKit (built here, on the main actor; a default argument could not be).
    init(store: HealthStoring? = nil, defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.store = store ?? HealthKitStore()
        self.defaults = defaults
        self.calendar = calendar
    }

    var isAvailable: Bool { store.isAvailable }

    /// Asks Health for exactly the switched-on types. False when the prompt could not be shown, or when writing
    /// was asked for and Health does not allow sharing menstrual flow (the switch then turns off). Read access
    /// cannot be checked: Health never reports it.
    func requestAuthorization(write: Bool, readTemperature: Bool, readSleep: Bool) async -> Bool {
        do {
            try await store.requestAuthorization(write: write, readTemperature: readTemperature, readSleep: readSleep)
            lastError = nil
            return !write || store.canWriteFlow
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Day keys RhythmX has written to Health and not taken back.
    var writtenDayKeys: Set<String> { Set(loadWritten().keys) }

    /// Mirrors the period days into Health: writes the days not written before and deletes the samples it
    /// wrote for days that are no longer period days (deleted, retyped or moved to Menopause). Archived cycles
    /// still count, so archiving never removes anything from Health. A failed save records nothing and a
    /// failed delete keeps the day recorded, so both are retried on the next sync. Only called while "Write
    /// period days" is on; turning it off leaves Health as it is.
    func writePeriodDays(from events: [Event], archivedBlocks: [ArchivedDataBlock]) async throws {
        let previous = writeTask
        let task = Task { @MainActor [weak self] in
            _ = try? await previous?.value
            try await self?.mirrorPeriodDays(from: events, archivedBlocks: archivedBlocks)
        }
        writeTask = task
        try await task.value
    }

    private func mirrorPeriodDays(from events: [Event], archivedBlocks: [ArchivedDataBlock]) async throws {
        var written = loadWritten()
        let days = HealthMapping.flowSamples(from: events, archivedBlocks: archivedBlocks, calendar: calendar)
        let desired = Dictionary(days.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
        var firstError: Error?
        func note(_ error: Error) { firstError = firstError ?? error }

        // 1. Days not in the record may already be in Health from an earlier install or another device: adopt
        //    this app's own samples for them instead of saving a second copy. Without the lookup nothing new is
        //    saved, since a save could duplicate.
        var lookupFailed = false
        let unrecorded = days.filter { written[$0.dayKey] == nil }
        if !unrecorded.isEmpty {
            do {
                let adopted = try await adoptOwnSamples(for: unrecorded, written: written)
                written.merge(adopted) { _, new in new }
            } catch {
                note(error)
                lookupFailed = true
            }
        }

        // A day recorded before the flag was kept is assumed to carry the current one.
        for (key, day) in desired where written[key] != nil && written[key]?.isCycleStart == nil {
            written[key]?.isCycleStart = day.isCycleStart
        }

        // 2. Take back days that stopped being period days, and days whose cycle-start flag changed (an earlier
        //    day joined the run, or the first day went); those are saved again below with the new flag.
        let toDelete = written.keys.filter { key in
            guard let day = desired[key] else { return true }
            return written[key]?.isCycleStart != day.isCycleStart
        }.sorted()
        var rewritable = Set<String>()
        if !toDelete.isEmpty {
            do {
                let ids = try await sampleIDs(for: toDelete, written: written)
                // A count short of `ids` means a sample was already gone (removed in Health or on another
                // device). That is the wanted end state, so the day leaves the record either way; the same goes
                // for an older day where no sample of this app was found.
                if !ids.isEmpty { _ = try await store.deleteFlowSamples(ids: ids) }
                for key in toDelete { written[key] = nil }
                rewritable = Set(toDelete)
            } catch {
                note(error)
            }
        }
        saveWritten(written)

        // 3. Save the days Health does not hold yet.
        let pending = days.filter { written[$0.dayKey] == nil && (!lookupFailed || rewritable.contains($0.dayKey)) }
        if !pending.isEmpty {
            do {
                let ids = try await store.saveFlowDays(pending)
                for day in pending {
                    written[day.dayKey] = WrittenDay(ids: ids[day.dayKey].map { [$0.uuidString] } ?? [],
                                                     isCycleStart: day.isCycleStart)
                }
                saveWritten(written)
            } catch {
                note(error)
            }
        }
        if let firstError { throw firstError }
    }

    /// This app's samples already in Health for `days`, each by the day it starts nearest to (within the
    /// 14-hour window). Samples already in the record are skipped. A day whose samples disagree on the
    /// cycle-start flag, or carry the wrong one, is recorded so that step 2 rewrites it.
    private func adoptOwnSamples(for days: [HealthMapping.FlowDay],
                                 written: [String: WrittenDay]) async throws -> [String: WrittenDay] {
        guard let first = days.first?.start, let last = days.last?.start else { return [:] }
        let window = HealthMapping.dayMatchWindow
        let found = try await store.ownFlowSamples(start: first.addingTimeInterval(-window),
                                                   end: last.addingTimeInterval(window))
        let known = Set(written.values.flatMap(\.ids))
        let byStart = Dictionary(days.map { ($0.start, $0) }, uniquingKeysWith: { first, _ in first })
        let starts = Array(byStart.keys)
        var adopted: [String: WrittenDay] = [:]
        for sample in found where !known.contains(sample.id.uuidString) {
            guard let start = HealthMapping.nearestDay(to: sample.start, in: starts), let day = byStart[start] else { continue }
            var entry = adopted[day.dayKey] ?? WrittenDay(ids: [], isCycleStart: sample.isCycleStart)
            entry.ids.append(sample.id.uuidString)
            if entry.isCycleStart != sample.isCycleStart { entry.isCycleStart = !day.isCycleStart }
            adopted[day.dayKey] = entry
        }
        return adopted
    }

    /// The sample IDs to delete for these day keys. Days recorded with IDs use them. Days recorded before IDs
    /// were kept look up this app's own samples starting within 14 hours of that day, skipping any sample that
    /// starts nearer another recorded day or whose ID is recorded for another day.
    private func sampleIDs(for keys: [String], written: [String: WrittenDay]) async throws -> Set<UUID> {
        var ids = Set<UUID>()
        var legacyStarts: [Date: String] = [:]
        for key in keys {
            let known = (written[key]?.ids ?? []).compactMap(UUID.init(uuidString:))
            if known.isEmpty {
                if let range = HealthMapping.dayRange(forKey: key, calendar: calendar) { legacyStarts[range.start] = key }
            } else {
                ids.formUnion(known)
            }
        }
        guard let first = legacyStarts.keys.min(), let last = legacyStarts.keys.max() else { return ids }
        let window = HealthMapping.dayMatchWindow
        let found = try await store.ownFlowSamples(start: first.addingTimeInterval(-window),
                                                   end: last.addingTimeInterval(window))
        let recordedIDs = Set(written.values.flatMap(\.ids))
        let recordedStarts = written.keys.compactMap { HealthMapping.dayRange(forKey: $0, calendar: calendar)?.start }
        for sample in found where !recordedIDs.contains(sample.id.uuidString) {
            guard let nearest = HealthMapping.nearestDay(to: sample.start, in: recordedStarts),
                  legacyStarts[nearest] != nil else { continue }
            ids.insert(sample.id)
        }
        return ids
    }

    /// The written-day record, with the older records (IDs without the flag, or day keys alone) folded in.
    private func loadWritten() -> [String: WrittenDay] {
        if let data = defaults.data(forKey: Self.writtenRecordsKey),
           let records = try? JSONDecoder().decode([String: WrittenDay].self, from: data) {
            return records
        }
        var written: [String: WrittenDay] = [:]
        for (key, ids) in (defaults.dictionary(forKey: Self.writtenSamplesKey) as? [String: [String]]) ?? [:] {
            written[key] = WrittenDay(ids: ids, isCycleStart: nil)
        }
        for key in defaults.stringArray(forKey: Self.writtenDaysKey) ?? [] where written[key] == nil {
            written[key] = WrittenDay(ids: [], isCycleStart: nil)
        }
        return written
    }

    private func saveWritten(_ written: [String: WrittenDay]) {
        guard let data = try? JSONEncoder().encode(written) else { return }
        defaults.set(data, forKey: Self.writtenRecordsKey)
        defaults.removeObject(forKey: Self.writtenSamplesKey)
        defaults.removeObject(forKey: Self.writtenDaysKey)
    }

    @discardableResult
    func importTemperatures(since: Date) async throws -> [PlanningInsights.TempPoint] {
        let points = HealthMapping.temperaturePoints(from: try await store.temperatureSamples(since: since), calendar: calendar)
        importedTemperatures = points
        return points
    }

    @discardableResult
    func importSleep(since: Date) async throws -> [Date: TimeInterval] {
        let summary = HealthMapping.sleepSummary(from: try await store.sleepSamples(since: since), calendar: calendar)
        importedSleep = summary
        return summary
    }

    /// The Health temperature for the day of `date`, for the tag form's pre-fill note.
    func temperature(on date: Date) -> Double? {
        importedTemperatures.first { calendar.isDate($0.date, inSameDayAs: date) }?.value
    }

    /// Applies the three toggles: mirrors period days while writing is on, refreshes or clears the imports.
    /// Each step runs even when an earlier one fails; the first error is kept in `lastError`. Nothing is
    /// retried in a loop.
    func refresh(events: [Event], archivedBlocks: [ArchivedDataBlock], settings: AppSettings) async {
        guard isAvailable else { return }
        let since = calendar.date(byAdding: .day, value: -Self.importWindowDays, to: Date()) ?? .distantPast
        var firstError: Error?
        if settings.healthWritePeriod {
            do { try await writePeriodDays(from: events, archivedBlocks: archivedBlocks) } catch { firstError = firstError ?? error }
        }
        if settings.healthReadTemperature {
            do { try await importTemperatures(since: since) } catch { firstError = firstError ?? error }
        } else {
            importedTemperatures = []
        }
        if settings.healthReadSleep {
            do { try await importSleep(since: since) } catch { firstError = firstError ?? error }
        } else {
            importedSleep = [:]
        }
        lastError = firstError?.localizedDescription
    }

    /// Mirrors period days whenever the events or archives change while "Write period days" is on. Called
    /// once at launch.
    func bind(eventStore: EventStore, archivedDataStore: ArchivedDataStore, settings: AppSettings) {
        cancellables.removeAll()
        eventStore.$events.combineLatest(archivedDataStore.$archivedBlocks)
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self, weak settings] events, blocks in
                guard let self, let settings, settings.healthWritePeriod else { return }
                Task { @MainActor in
                    do { try await self.writePeriodDays(from: events, archivedBlocks: blocks) } catch { self.lastError = error.localizedDescription }
                }
            }
            .store(in: &cancellables)
    }
}
