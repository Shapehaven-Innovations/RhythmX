//  DailyInsightsNotifier.swift
//  Delivers the Daily insights notification. The next seven days are always scheduled with the template's
//  note (`NotificationScheduler.dailyInsightRequests`), so a missed refresh still delivers one. A refresh then
//  writes the next note with `DailyInsightsService` (Apple Intelligence when available, the template
//  otherwise) and swaps it into that day's pending request. Refreshes run when the app becomes active, after
//  a tag is logged (debounced, off the main actor) and from a background app refresh about three hours
//  before the chosen time. Everything reads the stores' data from the shared store, so the background
//  refresh needs no UI.

import Foundation
import UserNotifications
import BackgroundTasks

/// Everything a note needs, read from the shared store.
struct DailyInsightsInput {
    var setting: DailyInsightsSetting
    var mode: TrackingMode
    var events: [Event]
    var archivedBlocks: [ArchivedDataBlock]
    var overrides: FertileOverrides

    /// The stores' on-disk data and the settings, as the app and the widgets write them.
    static func load(from defaults: UserDefaults = AppGroup.defaults) -> DailyInsightsInput {
        DailyInsightsInput(
            setting: DailyInsightsSetting.load(from: defaults),
            mode: defaults.string(forKey: "trackingMode").flatMap(TrackingMode.init(rawValue:)) ?? .cycle,
            events: PhaseWidgetSnapshot.loadEvents(from: defaults),
            archivedBlocks: defaults.data(forKey: PersistenceKeys.archivedData)
                .flatMap { try? JSONDecoder().decode([ArchivedDataBlock].self, from: $0) } ?? [],
            overrides: FertileWindow.loadOverrides(from: defaults)
        )
    }
}

/// Runs async jobs one after another, in the order they were queued, so a job never interleaves with another.
/// Each job carries the ticket its run took when it started; a job whose run started before one that has
/// already been applied is skipped, so an older run can never undo a newer one.
actor SerialJobQueue {
    private var tail: Task<Void, Never>?
    private var lastApplied = 0
    private var issued = 0

    func ticket() -> Int {
        issued += 1
        return issued
    }

    func run(ticket: Int, _ job: @escaping @Sendable () async -> Void) async {
        let previous = tail
        let task = Task {
            await previous?.value
            guard await self.claim(ticket) else { return }
            await job()
        }
        tail = task
        await task.value
    }

    private func claim(_ ticket: Int) -> Bool {
        guard ticket > lastApplied else { return false }
        lastApplied = ticket
        return true
    }
}

final class DailyInsightsNotifier: @unchecked Sendable {
    /// The written notes live apart from the Today cache, so writing tomorrow's note never pushes out today's.
    static let cacheKey = "dailyInsightsNotificationCache"

    private let center: InsightNotificationCenter
    private let writer: InsightWriting
    private let cache: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let reloadWidgets: () -> Void
    /// Every replace of the pending requests runs here, one at a time, so an older run can never add its
    /// requests after a newer run replaced them.
    private let queue = SerialJobQueue()

    init(center: InsightNotificationCenter = UNUserNotificationCenter.current(),
         writer: InsightWriting = FoundationModelsInsightWriter(),
         cache: UserDefaults = AppGroup.defaults,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init,
         reloadWidgets: @escaping () -> Void = AppGroup.reloadWidgets) {
        self.center = center
        self.writer = writer
        self.cache = cache
        self.calendar = calendar
        self.now = now
        self.reloadWidgets = reloadWidgets
    }

    /// Replaces every pending `rhythmx.insight.` request with the next seven days: the template's note, or the
    /// written one where it is cached for that day's facts. Nothing when off or not authorized. No writing here.
    func schedule(_ input: DailyInsightsInput) async {
        let ticket = await queue.ticket()
        let authorized = input.setting.isOn ? await center.isAuthorizedForInsights() : false
        let requests = NotificationScheduler.dailyInsightRequests(
            setting: input.setting, authorized: authorized, mode: input.mode, events: input.events,
            archivedBlocks: input.archivedBlocks, overrides: input.overrides, now: now(), calendar: calendar,
            written: { [self] fire, facts in service(for: fire).cachedInsights(for: facts) }
        )
        await replacePending(with: requests, ticket: ticket)
    }

    /// `schedule`, then writes the next note and schedules again with it. When the task is cancelled (a
    /// background refresh that ran out of time), the template notes already scheduled stay.
    func refresh(_ input: DailyInsightsInput) async {
        await schedule(input)
        guard input.setting.isOn, await center.isAuthorizedForInsights(),
              let fire = input.setting.nextFireDate(after: now(), calendar: calendar) else { return }
        let facts = InsightFacts.make(events: input.events, archivedBlocks: input.archivedBlocks, mode: input.mode,
                                      today: fire, fertileOverrides: input.overrides, calendar: calendar)
        _ = await service(for: fire).insights(for: facts)
        guard !Task.isCancelled else { return }
        await schedule(input)
        reloadWidgets()
    }

    /// The service as of `fire`'s day, so its cache key is that day.
    private func service(for fire: Date) -> DailyInsightsService {
        DailyInsightsService(writer: writer, defaults: cache, now: { fire }, storageKey: Self.cacheKey, calendar: calendar)
    }

    /// Queued (`SerialJobQueue`): runs finish in the order they started, so the last one to start decides
    /// what is pending.
    private func replacePending(with requests: [UNNotificationRequest], ticket: Int) async {
        let center = center
        await queue.run(ticket: ticket) {
            let stale = await center.pendingIdentifiers().filter { $0.hasPrefix(NotificationScheduler.insightPrefix) }
            if !stale.isEmpty { center.removePending(stale) }
            for request in requests { await center.addRequest(request) }
        }
    }
}

// MARK: - In the app

/// Runs the notifier off the main actor and coalesces bursts (several logs in a row, the app becoming active
/// while a refresh is waiting) into one run.
@MainActor
final class DailyInsightsCoordinator {
    static let shared = DailyInsightsCoordinator()

    private let notifier: DailyInsightsNotifier
    private var pending: Task<Void, Never>?
    private var pendingWrites = false

    init(notifier: DailyInsightsNotifier = DailyInsightsNotifier()) {
        self.notifier = notifier
    }

    /// Schedules the notes after a short pause; with `write`, also writes the next one. A write that is still
    /// waiting is kept when a plain reschedule comes in.
    func update(write: Bool, delay: Duration = .seconds(1)) {
        pending?.cancel()
        pendingWrites = pendingWrites || write
        let writes = pendingWrites
        let notifier = notifier
        pending = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let input = DailyInsightsInput.load()
            await self?.didStart()
            DailyInsightsBackground.submit(setting: input.setting)
            if writes && input.setting.isOn {
                await notifier.refresh(input)
            } else {
                await notifier.schedule(input)
            }
        }
    }

    private func didStart() { pendingWrites = false }
}

// MARK: - Background app refresh

/// The background app refresh: requested for about three hours before the chosen time. iOS decides the
/// moment (and only runs it with Background App Refresh on), so the template notes are always in place first.
/// The handler is attached with SwiftUI's `.backgroundTask(.appRefresh(_:))` in `AppEntry`; the identifier
/// is listed under `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
enum DailyInsightsBackground {
    static let taskIdentifier = "beta.Rhythm.dailyInsights"
    static let leadTime: TimeInterval = 3 * 60 * 60

    /// About three hours before the next note; when that moment has passed, three hours before the one after.
    /// Nil when Daily insights is off.
    static func earliestBeginDate(setting: DailyInsightsSetting, now: Date, calendar: Calendar = .current) -> Date? {
        guard setting.isOn else { return nil }
        return setting.fireDates(after: now, count: 2, calendar: calendar)
            .map { $0.addingTimeInterval(-leadTime) }
            .first { $0 > now }
    }

    /// Requests the next refresh, or cancels it when Daily insights is off. A failed submit (the Simulator,
    /// Background App Refresh off) is ignored: the template notes are already scheduled.
    static func submit(setting: DailyInsightsSetting, now: Date = Date()) {
        guard let begin = earliestBeginDate(setting: setting, now: now) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = begin
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The background refresh itself: asks for the next one, then writes the next note. SwiftUI cancels this
    /// task when the time runs out, and the notifier then keeps the template note.
    static func handle() async {
        let input = DailyInsightsInput.load()
        submit(setting: input.setting)
        guard input.setting.isOn else { return }
        await DailyInsightsNotifier().refresh(input)
    }
}
