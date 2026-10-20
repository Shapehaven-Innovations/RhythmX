//  CalendarSync.swift
//  One-way sync into a dedicated "RhythmX" calendar in Apple Calendar (Plus). The planner is pure and under
//  test; `CalendarSync` applies its diff with EventKit.
//
//  Access level (spike, Task 20): write-only access cannot read back events the app saved, cannot read the
//  calendar list and cannot create a calendar (WWDC23 "Discover Calendar and EventKit"). A dedicated calendar
//  that is updated when data changes and emptied when sync is turned off therefore needs FULL access. Every
//  read and write below is restricted to the "RhythmX" calendar: no predicate ever spans another calendar and
//  no other calendar's events are touched. Nothing leaves the device.
//
//  When Plus is no longer active the app stops syncing at once, but removes its events and turns the switch off
//  only after StoreKit has confirmed the lapse this session and the grace period is over (`CalendarSyncPolicy`).
//  The calendar is found by the identifier saved when the app created it, never by its title alone, and is never
//  deleted: only the app's own events are. Event notes and urls carry only an opaque key, never what the event is.

import Foundation
import Combine
import CryptoKit
import EventKit

// MARK: - Planner (pure)

/// Which kinds of items are synced. All on by default.
struct SyncOptions: Equatable {
    var periodDays = true
    var predictedPeriod = true
    var fertileWindow = true
    var phaseStarts = true

    var anyOn: Bool { periodDays || predictedPeriod || fertileWindow || phaseStarts }
}

/// One calendar event the app owns. `key` identifies it across syncs; all other fields are compared too, so a
/// changed title or date is a remove plus an add. All-day items use `start` and `end` as inclusive days.
struct SyncItem: Hashable {
    let key: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
}

/// The user's short symbols for discreet titles (Settings, Apple Calendar card). Each one is 1 or 2 letters or
/// digits, or a single emoji; anything else is dropped and an empty symbol falls back to the default. The
/// predicted period uses the period symbol.
struct DiscreetSymbols: Equatable {
    /// The one place the default symbols are defined.
    private static let fallback = (period: "R", fertileWindow: "F", phaseStart: "P")
    static let maxLength = 2

    static let `default` = DiscreetSymbols()

    let period: String
    let fertileWindow: String
    let phaseStart: String

    init(period: String = "", fertileWindow: String = "", phaseStart: String = "") {
        self.period = Self.sanitize(period, fallback: Self.fallback.period)
        self.fertileWindow = Self.sanitize(fertileWindow, fallback: Self.fallback.fertileWindow)
        self.phaseStart = Self.sanitize(phaseStart, fallback: Self.fallback.phaseStart)
    }

    /// The defaults, for placeholders in Settings.
    static var defaultPeriod: String { fallback.period }
    static var defaultFertileWindow: String { fallback.fertileWindow }
    static var defaultPhaseStart: String { fallback.phaseStart }

    static func sanitize(_ raw: String, fallback: String) -> String {
        let cleaned = clean(raw)
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// What is kept of `raw`, possibly empty: whitespace trimmed, then a single emoji when it starts with one,
    /// else its first two letters or digits.
    static func clean(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, isEmoji(first) { return String(first) }
        return String(trimmed.filter { ($0.isLetter || $0.isNumber) && !isEmoji($0) }.prefix(maxLength))
    }

    private static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
    }
}

/// The only place event titles are defined.
enum CalendarSyncTitles {
    enum Kind: CaseIterable { case period, predictedPeriod, fertileWindow, phaseStart }

    static let plain: [Kind: String] = [
        .period: "Period",
        .predictedPeriod: "Predicted period",
        .fertileWindow: "Fertile window",
        .phaseStart: "%@ phase starts",
    ]

    /// The discreet table for a set of symbols, for calendars shared with others.
    static func discreet(_ symbols: DiscreetSymbols) -> [Kind: String] {
        [
            .period: symbols.period,
            .predictedPeriod: symbols.period,
            .fertileWindow: symbols.fertileWindow,
            .phaseStart: symbols.phaseStart,
        ]
    }

    /// The default discreet table.
    static var discreet: [Kind: String] { discreet(.default) }

    static func title(_ kind: Kind, phase: Event.EventType? = nil, discreet: Bool,
                      symbols: DiscreetSymbols = .default) -> String {
        let table = discreet ? Self.discreet(symbols) : plain
        let text = table[kind] ?? ""
        guard kind == .phaseStart, !discreet else { return text }
        return String(format: text, (phase?.rawValue ?? "").capitalized)
    }
}

enum CalendarSyncPlanner {
    /// The events the app should have in its calendar for this data. Menopause events and archives never take
    /// part. Period days and fertile days are merged into one all-day run each; phase starts and the predicted
    /// period are single all-day items. A predicted day already in the past is left out.
    static func items(events: [Event], archivedBlocks: [ArchivedDataBlock], options: SyncOptions, discreet: Bool,
                      symbols: DiscreetSymbols = .default, today: Date, overrides: FertileOverrides = FertileOverrides(),
                      calendar: Calendar = .current) -> [SyncItem] {
        let cycleEvents = events.filter { $0.effectiveMode != .menopause }
        let cycleBlocks = archivedBlocks.filter { $0.effectiveMode != .menopause }
        let today = calendar.startOfDay(for: today)
        var result: [SyncItem] = []

        func key(_ date: Date) -> String { FertileWindow.dayKey(date, calendar: calendar) }

        if options.periodDays {
            let days = Set(cycleEvents.filter { $0.eventType == .menstrual }.map { calendar.startOfDay(for: $0.date) })
            for run in runs(of: days, calendar: calendar) {
                result.append(SyncItem(key: "period-\(key(run.first))-\(key(run.last))",
                                       title: CalendarSyncTitles.title(.period, discreet: discreet, symbols: symbols),
                                       start: run.first, end: run.last, isAllDay: true))
            }
        }

        if options.fertileWindow {
            let days = Set(FertileWindow.days(events: cycleEvents, overrides: overrides, calendar: calendar)
                .compactMap { PlanningInsights.date(fromDayKey: $0, calendar: calendar) })
            for run in runs(of: days, calendar: calendar) {
                result.append(SyncItem(key: "fertile-\(key(run.first))-\(key(run.last))",
                                       title: CalendarSyncTitles.title(.fertileWindow, discreet: discreet, symbols: symbols),
                                       start: run.first, end: run.last, isAllDay: true))
            }
        }

        if options.phaseStarts {
            for phase in [Event.EventType.follicular, .ovulation, .luteal] {
                let days = Set(cycleEvents.filter { $0.eventType == phase }.map { calendar.startOfDay(for: $0.date) })
                for run in runs(of: days, calendar: calendar) {
                    result.append(SyncItem(key: "phase-\(phase.rawValue)-\(key(run.first))",
                                           title: CalendarSyncTitles.title(.phaseStart, phase: phase, discreet: discreet,
                                                                           symbols: symbols),
                                           start: run.first, end: run.first, isAllDay: true))
                }
            }
        }

        if options.predictedPeriod,
           let predicted = predictedPeriod(events: cycleEvents, archivedBlocks: cycleBlocks, calendar: calendar),
           predicted >= today {
            result.append(SyncItem(key: "predicted-\(key(predicted))",
                                   title: CalendarSyncTitles.title(.predictedPeriod, discreet: discreet, symbols: symbols),
                                   start: predicted, end: predicted, isAllDay: true))
        }

        return result.sorted { ($0.start, $0.key) < ($1.start, $1.key) }
    }

    /// The next period estimate the Calendar tab shows: the current cycle's start plus its span when there is a
    /// current cycle, else `CyclePredictionService` over the archives.
    static func predictedPeriod(events: [Event], archivedBlocks: [ArchivedDataBlock], calendar: Calendar) -> Date? {
        let dates = events.map { calendar.startOfDay(for: $0.date) }
        if let first = dates.min(), let last = dates.max() {
            let span = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
            return calendar.date(byAdding: .day, value: span, to: first)
        }
        return CyclePredictionService.predictedStartDate(from: archivedBlocks).map { calendar.startOfDay(for: $0) }
    }

    /// What to create and what to delete so the calendar holds exactly `desired`.
    static func diff(existing: Set<SyncItem>, desired: Set<SyncItem>) -> (add: [SyncItem], remove: [SyncItem]) {
        let add = desired.subtracting(existing).sorted { ($0.start, $0.key) < ($1.start, $1.key) }
        let remove = existing.subtracting(desired).sorted { ($0.start, $0.key) < ($1.start, $1.key) }
        return (add, remove)
    }

    /// Consecutive days grouped into (first, last) runs, oldest first.
    static func runs(of days: Set<Date>, calendar: Calendar) -> [(first: Date, last: Date)] {
        var result: [(first: Date, last: Date)] = []
        for day in days.sorted() {
            if let previous = result.last,
               let next = calendar.date(byAdding: .day, value: 1, to: previous.last), next == day {
                result[result.count - 1].last = day
            } else {
                result.append((day, day))
            }
        }
        return result
    }
}

/// The sync options as stored in Settings. Lives here, not in AppSettings, so that file keeps compiling in the
/// widget target, which has no EventKit types.
extension AppSettings {
    var calendarSyncOptions: SyncOptions {
        SyncOptions(periodDays: calendarSyncPeriodDays, predictedPeriod: calendarSyncPredictedPeriod,
                    fertileWindow: calendarSyncFertileWindow, phaseStarts: calendarSyncPhaseStarts)
    }

    /// The discreet symbols as stored (raw, possibly blank), sanitized.
    var calendarSyncSymbols: DiscreetSymbols {
        DiscreetSymbols(period: calendarSyncSymbolPeriod, fertileWindow: calendarSyncSymbolFertile,
                        phaseStart: calendarSyncSymbolPhase)
    }
}

// MARK: - Policy (pure)

/// What the app does with Apple Calendar sync on launch, on foreground, on an entitlement change and when data
/// changes. While Plus is active and the switch is on it syncs. When Plus is not active, new data stops being
/// synced at once, but nothing is removed until the lapse is confirmed: StoreKit answered this session
/// (`verified`) and the lapse is past `Entitlement.plusGrace` and not in a billing grace or retry period
/// (`withinGrace`). A confirmed lapse removes every event the app created, once, and turns the switch off;
/// without calendar access the switch still goes off and the removal waits (`pendingRemoval`) until access
/// returns. A removal that has not succeeded yet is retried on the next reconcile, but only while the switch is
/// off and either Plus is active or the lapse is still confirmed, so a stale cache never deletes anything.
enum CalendarSyncPolicy {
    enum Action: Equatable {
        case sync
        /// Plus and the switch is on, but calendar access is gone.
        case reportNoAccess
        case removeAllAndDisable
        /// A confirmed lapse without calendar access: switch off, removal pending until access returns.
        case disableAndDeferRemoval
        /// A removal that failed or waited for access, tried again.
        case retryRemoval
        case none
    }

    static func action(isPlus: Bool, syncOn: Bool, hasAccess: Bool, verified: Bool, withinGrace: Bool,
                       pendingRemoval: Bool = false) -> Action {
        let lapseConfirmed = !isPlus && verified && !withinGrace
        if syncOn {
            if isPlus { return hasAccess ? .sync : .reportNoAccess }
            guard lapseConfirmed else { return .none }
            return hasAccess ? .removeAllAndDisable : .disableAndDeferRemoval
        }
        if pendingRemoval, hasAccess, isPlus || lapseConfirmed { return .retryRemoval }
        return .none
    }
}

// MARK: - Store

/// The calendar the app writes to. `EventKitCalendarStore` is the real one; tests use a fake.
@MainActor
protocol CalendarSyncStore: AnyObject {
    var hasAccess: Bool { get }
    func requestAccess() async throws -> Bool
    /// Makes the "RhythmX" calendar hold exactly `desired` among the app's own events.
    func replaceItems(with desired: Set<SyncItem>) throws
    /// Deletes every event the app created. The calendar itself stays. Never touches another calendar.
    func removeAll() throws
}

// MARK: - Coordinator

@MainActor
final class CalendarSync: ObservableObject {
    static let calendarTitle = "RhythmX"
    /// Every app event carries an opaque form of its planner key here, so it can be found again without reading
    /// anything else and without the notes saying what the event is.
    static let keyPrefix = "rhythmx-sync:"

    enum SyncError: LocalizedError {
        case accessDenied
        case noCalendarSource

        var errorDescription: String? {
            switch self {
            case .accessDenied:     return "RhythmX has no access to your calendars. You can change this in iOS Settings."
            case .noCalendarSource: return "No calendar account could hold the RhythmX calendar."
            }
        }
    }

    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncedAt: Date?
    /// Sync is on but calendar access is gone (revoked in iOS Settings). The Calendar tab hides its chip and the
    /// Settings card shows `lastError`.
    @Published private(set) var accessDenied = false

    private let store: CalendarSyncStore
    private let calendar: Calendar
    private var cancellables = Set<AnyCancellable>()
    /// A removal in progress; overlapping triggers do not start a second one.
    private var removalInFlight = false

    init(store: CalendarSyncStore? = nil, calendar: Calendar = .current) {
        self.store = store ?? EventKitCalendarStore(calendar: calendar)
        self.calendar = calendar
    }

    var hasAccess: Bool { store.hasAccess }

    /// Full access (see the header for why). False when denied.
    func requestAccess() async -> Bool {
        if hasAccess { return true }
        do {
            let granted = try await store.requestAccess()
            if !granted { lastError = SyncError.accessDenied.errorDescription }
            accessDenied = !granted
            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Makes the "RhythmX" calendar hold exactly the planned items.
    func sync(events: [Event], archivedBlocks: [ArchivedDataBlock], overrides: FertileOverrides,
              options: SyncOptions, discreet: Bool, symbols: DiscreetSymbols = .default,
              today: Date = Date()) async throws {
        guard hasAccess else { throw SyncError.accessDenied }
        let desired = Set(CalendarSyncPlanner.items(events: events, archivedBlocks: archivedBlocks, options: options,
                                                    discreet: discreet, symbols: symbols, today: today,
                                                    overrides: overrides, calendar: calendar))
        try store.replaceItems(with: desired)
        lastSyncedAt = Date()
        lastError = nil
    }

    /// The sync the app runs on its own (launch, foreground, entitlement and data changes, option changes in
    /// Settings), following `CalendarSyncPolicy`. Errors land in `lastError`. On a confirmed lapse the switch is
    /// turned off and the removal marked pending before it starts, so overlapping triggers find it off, and a
    /// removal that fails is tried again on the next reconcile until one succeeds.
    /// - Parameters:
    ///   - isPlus: Plus without grace (`PurchaseStore.isPlus`); syncing stops as soon as it is false.
    ///   - verified: `PurchaseStore.entitlementVerifiedThisSession`.
    ///   - withinGrace: `PurchaseStore.isWithinPlusGrace`.
    func reconcile(events: [Event], archivedBlocks: [ArchivedDataBlock], overrides: FertileOverrides,
                   settings: AppSettings, isPlus: Bool, verified: Bool, withinGrace: Bool,
                   today: Date = Date()) async {
        let action = CalendarSyncPolicy.action(isPlus: isPlus, syncOn: settings.calendarSyncOn, hasAccess: hasAccess,
                                               verified: verified, withinGrace: withinGrace,
                                               pendingRemoval: settings.calendarSyncPendingRemoval)
        switch action {
        case .none:
            return
        case .sync:
            accessDenied = false
            do {
                try await sync(events: events, archivedBlocks: archivedBlocks, overrides: overrides,
                               options: settings.calendarSyncOptions, discreet: settings.calendarSyncDiscreet,
                               symbols: settings.calendarSyncSymbols, today: today)
                // A full sync leaves exactly the planned events, so nothing older is waiting to go.
                settings.calendarSyncPendingRemoval = false
            } catch {
                lastError = error.localizedDescription
            }
        case .reportNoAccess:
            accessDenied = true
            lastError = SyncError.accessDenied.errorDescription
        case .disableAndDeferRemoval:
            settings.calendarSyncOn = false
            settings.calendarSyncPendingRemoval = true
            accessDenied = true
            lastError = SyncError.accessDenied.errorDescription
        case .removeAllAndDisable:
            settings.calendarSyncOn = false
            settings.calendarSyncPendingRemoval = true
            await turnOff(settings: settings)
        case .retryRemoval:
            await turnOff(settings: settings)
        }
    }

    /// The entitlement as the policy reads it, so a change in any part re-runs `reconcile`.
    private struct EntitlementInputs: Equatable {
        let isPlus: Bool
        let verified: Bool
        let withinGrace: Bool
    }

    /// Re-syncs whenever events, archives or the fertile window change, and applies the policy whenever the
    /// entitlement or its verification changes (a purchase, a renewal, an expiry, a refund, or StoreKit
    /// answering after launch). Called once at launch.
    func bind(eventStore: EventStore, archivedDataStore: ArchivedDataStore, fertileStore: FertileStore,
              settings: AppSettings, purchaseStore: PurchaseStore) {
        cancellables.removeAll()
        Publishers.CombineLatest3(eventStore.$events, archivedDataStore.$archivedBlocks, fertileStore.$overrides)
            .dropFirst()
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self, weak settings, weak purchaseStore] events, blocks, overrides in
                guard let self, let settings, let purchaseStore else { return }
                Task { @MainActor in
                    await self.reconcile(events: events, archivedBlocks: blocks, overrides: overrides,
                                         settings: settings, isPlus: purchaseStore.isPlus,
                                         verified: purchaseStore.entitlementVerifiedThisSession,
                                         withinGrace: purchaseStore.isWithinPlusGrace)
                }
            }
            .store(in: &cancellables)
        // `@Published` fires before the value is stored, so everything is read from the emitted values.
        Publishers.CombineLatest3(purchaseStore.$entitlement, purchaseStore.$entitlementVerifiedThisSession,
                                  purchaseStore.$plusRenewalState)
            .dropFirst()
            .map { [weak purchaseStore] entitlement, verified, renewal -> EntitlementInputs in
                let now = purchaseStore?.currentDate() ?? Date()
                return EntitlementInputs(isPlus: entitlement.isPlus(now: now, grace: 0), verified: verified,
                                         withinGrace: Entitlement.isWithinGrace(entitlement, now: now, renewal: renewal))
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak settings, weak eventStore, weak archivedDataStore, weak fertileStore] inputs in
                guard let self, let settings, let eventStore, let archivedDataStore, let fertileStore else { return }
                Task { @MainActor in
                    await self.reconcile(events: eventStore.events, archivedBlocks: archivedDataStore.archivedBlocks,
                                         overrides: fertileStore.overrides, settings: settings, isPlus: inputs.isPlus,
                                         verified: inputs.verified, withinGrace: inputs.withinGrace)
                }
            }
            .store(in: &cancellables)
    }

    /// The switch went off (by hand, or after a confirmed lapse): remove everything the app created, keeping
    /// any error for Settings to show. `settings.calendarSyncPendingRemoval` is cleared only when the removal
    /// succeeds. Without calendar access nothing can be removed and the removal stays pending.
    func turnOff(settings: AppSettings) async {
        settings.calendarSyncPendingRemoval = true
        guard hasAccess else {
            accessDenied = true
            return
        }
        guard !removalInFlight else { return }
        removalInFlight = true
        defer { removalInFlight = false }
        do {
            try await removeAll()
            settings.calendarSyncPendingRemoval = false
            accessDenied = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Deletes every event the app created. The "RhythmX" calendar itself is kept.
    func removeAll() async throws {
        guard hasAccess else { return }
        try store.removeAll()
        lastSyncedAt = nil
    }

    // MARK: Stored key

    /// The key written into an event's notes and url: a stable hash of the planner key, so neither field says
    /// what the event is (the planner key names the kind and the dates).
    static func storedKey(for plannerKey: String) -> String {
        let digest = SHA256.hash(data: Data(plannerKey.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func notes(forStoredKey key: String) -> String { keyPrefix + key }

    static func url(forStoredKey key: String) -> URL? { URL(string: "rhythmx://sync/\(key)") }

    /// The stored key of an app event, from its notes or else its url; nil for an event the app did not create.
    static func storedKey(fromNotes notes: String?, url: URL?) -> String? {
        if let notes, let range = notes.range(of: keyPrefix) {
            let rest = notes[range.upperBound...]
            return String(rest.prefix { !$0.isNewline })
        }
        if let url, url.scheme == "rhythmx", url.host == "sync" {
            return url.lastPathComponent
        }
        return nil
    }
}

// MARK: - EventKit

@MainActor
final class EventKitCalendarStore: CalendarSyncStore {
    /// How far around today existing app events are looked up (only inside the "RhythmX" calendar).
    static let lookbackDays = 400
    static let lookaheadDays = 120
    /// The `calendarIdentifier` of the calendar the app created. The calendar is found by this, never by title.
    static let calendarIdentifierKey = "calendarSyncCalendarIdentifier"

    private let store = EKEventStore()
    private let calendar: Calendar
    private let defaults: UserDefaults

    init(calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        self.calendar = calendar
        self.defaults = defaults
    }

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func replaceItems(with desired: Set<SyncItem>) throws {
        guard hasAccess else { throw CalendarSync.SyncError.accessDenied }
        // Compared as stored: the planner key is replaced by its opaque form.
        let stored = Set(desired.map(Self.stored))
        guard let ekCalendar = try ownCalendar(createIfMissing: !stored.isEmpty) else { return }
        let existing = ownEvents(in: ekCalendar)
        let diff = CalendarSyncPlanner.diff(existing: Set(existing.keys), desired: stored)
        for item in diff.remove {
            if let event = existing[item] { try store.remove(event, span: .thisEvent, commit: false) }
        }
        for item in diff.add {
            try store.save(makeEvent(item, in: ekCalendar), span: .thisEvent, commit: false)
        }
        try store.commit()
    }

    /// Removes only the app's own events. The calendar is never deleted: it may hold events she added herself,
    /// and an empty calendar is harmless and is reused when sync is turned on again.
    func removeAll() throws {
        guard hasAccess, let ekCalendar = try ownCalendar(createIfMissing: false) else { return }
        for event in ownEvents(in: ekCalendar).values {
            try store.remove(event, span: .thisEvent, commit: false)
        }
        try store.commit()
    }

    private static func stored(_ item: SyncItem) -> SyncItem {
        SyncItem(key: CalendarSync.storedKey(for: item.key), title: item.title,
                 start: item.start, end: item.end, isAllDay: item.isAllDay)
    }

    // MARK: Calendar

    /// The app's calendar: the one whose identifier was saved when the app created it, if it still exists and
    /// can be written. Without a usable saved identifier (a reinstall, or an iCloud reset that changed it), a
    /// writable "RhythmX" calendar is adopted only when it already holds events carrying the app's key; a
    /// calendar that merely has the title is never used. Otherwise a new one is created when asked.
    private func ownCalendar(createIfMissing: Bool) throws -> EKCalendar? {
        if let id = defaults.string(forKey: Self.calendarIdentifierKey),
           let saved = store.calendar(withIdentifier: id), saved.allowsContentModifications {
            return saved
        }
        if let adopted = store.calendars(for: .event).first(where: {
            $0.title == CalendarSync.calendarTitle && $0.allowsContentModifications && !ownEvents(in: $0).isEmpty
        }) {
            defaults.set(adopted.calendarIdentifier, forKey: Self.calendarIdentifierKey)
            return adopted
        }
        guard createIfMissing else { return nil }
        return try createCalendar()
    }

    /// iCloud first so her other devices see it, then this device only, then wherever new events go by default.
    /// Each source is tried in turn; a source that refuses the calendar falls through to the next.
    private func createCalendar() throws -> EKCalendar {
        var candidates: [EKSource] = []
        func add(_ source: EKSource?) {
            guard let source, !candidates.contains(where: { $0.sourceIdentifier == source.sourceIdentifier }) else { return }
            candidates.append(source)
        }
        add(store.sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") })
        add(store.sources.first { $0.sourceType == .local })
        add(store.defaultCalendarForNewEvents?.source)
        var lastError: Error?
        for source in candidates {
            let created = EKCalendar(for: .event, eventStore: store)
            created.title = CalendarSync.calendarTitle
            created.source = source
            do {
                try store.saveCalendar(created, commit: true)
                defaults.set(created.calendarIdentifier, forKey: Self.calendarIdentifierKey)
                return created
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CalendarSync.SyncError.noCalendarSource
    }

    // MARK: Events (RhythmX calendar only)

    private func allEvents(in ekCalendar: EKCalendar) -> [EKEvent] {
        let now = Date()
        guard let start = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: now),
              let end = calendar.date(byAdding: .day, value: Self.lookaheadDays, to: now) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [ekCalendar])
        return store.events(matching: predicate)
    }

    /// The app's own events (those carrying a planner key) as items, for the diff.
    private func ownEvents(in ekCalendar: EKCalendar) -> [SyncItem: EKEvent] {
        var result: [SyncItem: EKEvent] = [:]
        for event in allEvents(in: ekCalendar) {
            guard let key = Self.key(of: event) else { continue }
            let item = SyncItem(key: key, title: event.title ?? "",
                                start: calendar.startOfDay(for: event.startDate),
                                end: calendar.startOfDay(for: event.endDate),
                                isAllDay: event.isAllDay)
            if result[item] == nil { result[item] = event }
        }
        return result
    }

    private func makeEvent(_ item: SyncItem, in ekCalendar: EKCalendar) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = ekCalendar
        event.title = item.title
        event.isAllDay = item.isAllDay
        event.startDate = item.start
        event.endDate = item.end
        // `item.key` is already the opaque stored key (see `replaceItems`).
        event.url = CalendarSync.url(forStoredKey: item.key)
        event.notes = CalendarSync.notes(forStoredKey: item.key)
        return event
    }

    /// Any event carrying the app's key prefix is the app's own, whatever key form it carries: one written by
    /// an older build is not in the desired set and is removed by the next sync.
    static func key(of event: EKEvent) -> String? {
        CalendarSync.storedKey(fromNotes: event.notes, url: event.url)
    }
}
