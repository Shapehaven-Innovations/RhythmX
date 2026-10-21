import XCTest
@testable import RhythmX

/// Apple Calendar sync when Plus is not active: the pure decision, and the flow against a fake calendar store
/// (EventKit itself is not under test). A lapse removes every app event once and turns the switch off.
@MainActor
final class CalendarSyncPolicyTests: XCTestCase {

    // MARK: - Fake store

    final class FakeStore: CalendarSyncStore {
        var hasAccess = true
        var items: Set<SyncItem> = []
        var replaceCount = 0
        var removeAllCount = 0
        var removeAllError: Error?
        var syncsOffDevice = false

        func requestAccess() async throws -> Bool { hasAccess }
        func replaceItems(with desired: Set<SyncItem>) throws {
            replaceCount += 1
            items = desired
        }
        func removeAll() throws {
            removeAllCount += 1
            if let removeAllError { throw removeAllError }
            items = []
        }
    }

    struct Failure: LocalizedError { var errorDescription: String? { "The calendar could not be changed." } }

    // MARK: - Settings isolation

    private let standardKeys = ["calendarSyncOn", "calendarSyncDiscreet", "calendarSyncPeriodDays",
                                "calendarSyncPredictedPeriod", "calendarSyncFertileWindow", "calendarSyncPhaseStarts",
                                "calendarSyncPendingRemoval"]
    private let groupKeys = ["calendarSyncSymbolPeriod", "calendarSyncSymbolFertile", "calendarSyncSymbolPhase"]
    private var savedStandard: [String: Any] = [:]
    private var savedGroup: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in standardKeys { savedStandard[key] = UserDefaults.standard.object(forKey: key); UserDefaults.standard.removeObject(forKey: key) }
        for key in groupKeys { savedGroup[key] = AppGroup.defaults.object(forKey: key); AppGroup.defaults.removeObject(forKey: key) }
    }

    override func tearDown() {
        for key in standardKeys {
            if let value = savedStandard[key] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        for key in groupKeys {
            if let value = savedGroup[key] { AppGroup.defaults.set(value, forKey: key) } else { AppGroup.defaults.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    private let anchor = Calendar.current.date(from: DateComponents(year: 2024, month: 5, day: 1))!
    private var cycle: [Event] { CycleGenerator.events(startDate: anchor, cycleLength: 28) }
    private var today: Date { Calendar.current.date(byAdding: .day, value: 10, to: anchor)! }

    /// A Plus user, or a lapse the store has confirmed (StoreKit answered this session, past the grace period).
    private func reconcile(_ sync: CalendarSync, _ settings: AppSettings, isPlus: Bool,
                           verified: Bool = true, withinGrace: Bool? = nil) async {
        await sync.reconcile(events: cycle, archivedBlocks: [], overrides: FertileOverrides(), settings: settings,
                             isPlus: isPlus, verified: verified, withinGrace: withinGrace ?? isPlus, today: today)
    }

    private func action(isPlus: Bool, syncOn: Bool = true, hasAccess: Bool = true, verified: Bool = true,
                        withinGrace: Bool = false, pending: Bool = false) -> CalendarSyncPolicy.Action {
        CalendarSyncPolicy.action(isPlus: isPlus, syncOn: syncOn, hasAccess: hasAccess, verified: verified,
                                  withinGrace: withinGrace, pendingRemoval: pending)
    }

    // MARK: - Where the RhythmX calendar lives

    func testTheCalendarPrefersTheOnDeviceSource() {
        let local = CalendarSourceCandidate(id: "L", kind: .local)
        let iCloud = CalendarSourceCandidate(id: "I", kind: .iCloud)
        let exchange = CalendarSourceCandidate(id: "E", kind: .other)
        XCTAssertEqual(CalendarSourcePlanner.order(sources: [iCloud, exchange, local], defaultSource: exchange),
                       [local, iCloud, exchange], "On My iPhone first, so nothing syncs off the device")
        XCTAssertEqual(CalendarSourcePlanner.order(sources: [iCloud, exchange], defaultSource: exchange), [iCloud, exchange],
                       "iCloud only setups fall back to the earlier choice")
        XCTAssertEqual(CalendarSourcePlanner.order(sources: [exchange, local], defaultSource: nil), [local])
        XCTAssertEqual(CalendarSourcePlanner.order(sources: [], defaultSource: iCloud), [iCloud])
        XCTAssertFalse(CalendarSourcePlanner.syncsOffDevice(local))
        XCTAssertTrue(CalendarSourcePlanner.syncsOffDevice(iCloud))
        XCTAssertTrue(CalendarSourcePlanner.syncsOffDevice(exchange))
    }

    func testAnOffDeviceCalendarIsDisclosed() async throws {
        let store = FakeStore()
        let sync = CalendarSync(store: store)
        try await sync.sync(events: cycle, archivedBlocks: [], overrides: FertileOverrides(), options: SyncOptions(),
                            discreet: false, today: today)
        XCTAssertNil(sync.offDeviceNote)

        store.syncsOffDevice = true
        try await sync.sync(events: cycle, archivedBlocks: [], overrides: FertileOverrides(), options: SyncOptions(),
                            discreet: false, today: today)
        XCTAssertEqual(sync.offDeviceNote, CalendarSync.iCloudDisclosure)
        XCTAssertEqual(CalendarSync.iCloudDisclosure,
                       "Your calendars are stored in iCloud, so this calendar will sync through your iCloud account.")
        let info = InfoCopy.appleCalendar.paragraphs.joined(separator: " ")
        XCTAssertFalse(info.contains("Nothing leaves this device"), "the fallback can sync it, so this is not claimed")
        XCTAssertTrue(info.contains("iCloud"))
    }

    // MARK: - Policy

    func testPolicyDecisions() {
        XCTAssertEqual(action(isPlus: true, withinGrace: true), .sync)
        XCTAssertEqual(action(isPlus: true, verified: false, withinGrace: true), .sync, "syncing needs no verification")
        XCTAssertEqual(action(isPlus: false), .removeAllAndDisable, "verified lapse past grace")
        XCTAssertEqual(action(isPlus: true, hasAccess: false, withinGrace: true), .reportNoAccess)
        XCTAssertEqual(action(isPlus: false, hasAccess: false), .disableAndDeferRemoval,
                       "access revoked: the switch goes off and the removal waits for access")
        XCTAssertEqual(action(isPlus: false, syncOn: false), .none, "already off: no repeated removal")
        XCTAssertEqual(action(isPlus: true, syncOn: false, withinGrace: true), .none)
        XCTAssertEqual(action(isPlus: false, syncOn: false, hasAccess: false), .none)
        XCTAssertEqual(action(isPlus: true, syncOn: false, hasAccess: false, withinGrace: true), .none)
    }

    func testStaleCachedExpiryBeforeVerificationNeverRemoves() {
        // Launch with a cached expiry in the past, before StoreKit has answered.
        XCTAssertEqual(action(isPlus: false, verified: false, withinGrace: false), .none)
        XCTAssertEqual(action(isPlus: false, hasAccess: false, verified: false), .none, "the switch is not turned off either")
        XCTAssertEqual(action(isPlus: false, syncOn: false, verified: false, pending: true), .none,
                       "a pending removal also waits for verification")
    }

    func testLapseWithinGraceNeverRemoves() {
        XCTAssertEqual(action(isPlus: false, withinGrace: true), .none, "inside the 3-day grace")
        XCTAssertEqual(action(isPlus: false, hasAccess: false, withinGrace: true), .none)
        XCTAssertEqual(action(isPlus: false, syncOn: false, withinGrace: true, pending: true), .none)
    }

    func testBillingRetryAndGracePeriodCountAsWithinGrace() {
        let expired = Entitlement(plusExpiry: Date(timeIntervalSince1970: 0), dayPassExpiry: nil)
        let now = Date()
        XCTAssertTrue(Entitlement.isWithinGrace(expired, now: now, renewal: .inBillingRetry))
        XCTAssertTrue(Entitlement.isWithinGrace(expired, now: now, renewal: .inGracePeriod))
        XCTAssertTrue(Entitlement.isWithinGrace(expired, now: now, renewal: .active))
        XCTAssertFalse(Entitlement.isWithinGrace(expired, now: now, renewal: .expired))
        XCTAssertFalse(Entitlement.isWithinGrace(expired, now: now, renewal: nil), "no status: the dates decide")
        let recent = Entitlement(plusExpiry: now.addingTimeInterval(-86_400), dayPassExpiry: nil)
        XCTAssertTrue(Entitlement.isWithinGrace(recent, now: now, renewal: .expired), "one day past expiry is within grace")
        XCTAssertFalse(Entitlement.isWithinGrace(.none, now: now, renewal: nil), "never subscribed or refunded")
    }

    func testPendingRemovalIsRetried() {
        XCTAssertEqual(action(isPlus: false, syncOn: false, pending: true), .retryRemoval)
        XCTAssertEqual(action(isPlus: false, syncOn: false, hasAccess: false, pending: true), .none, "waits for access")
        XCTAssertEqual(action(isPlus: true, syncOn: false, withinGrace: true, pending: true), .retryRemoval,
                       "the switch is off, so the calendar should be empty")
    }

    // MARK: - Flow

    func testPlusSyncsIntoTheStore() async {
        let store = FakeStore()
        let sync = CalendarSync(store: store)
        let settings = AppSettings()
        settings.calendarSyncOn = true

        await reconcile(sync, settings, isPlus: true)

        XCTAssertEqual(store.replaceCount, 1)
        XCTAssertFalse(store.items.isEmpty)
        XCTAssertTrue(settings.calendarSyncOn)
        XCTAssertNil(sync.lastError)
    }

    func testVerifiedLapsePastGraceRemovesEverythingOnceAndTurnsTheSwitchOff() async {
        let store = FakeStore()
        let sync = CalendarSync(store: store)
        let settings = AppSettings()
        settings.calendarSyncOn = true
        await reconcile(sync, settings, isPlus: true)
        XCTAssertFalse(store.items.isEmpty)

        await reconcile(sync, settings, isPlus: false)
        XCTAssertEqual(store.removeAllCount, 1)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(settings.calendarSyncOn, "the switch is left off")
        XCTAssertFalse(settings.calendarSyncPendingRemoval, "cleared once the removal succeeded")
        XCTAssertEqual(store.replaceCount, 1, "nothing is synced while Plus is off")

        // Launch, foreground and entitlement changes all land here again: no further work.
        await reconcile(sync, settings, isPlus: false)
        await reconcile(sync, settings, isPlus: false)
        XCTAssertEqual(store.removeAllCount, 1)

        // Plus comes back: the switch stays off until she turns it on again.
        await reconcile(sync, settings, isPlus: true)
        XCTAssertEqual(store.replaceCount, 1)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testStaleExpiryBeforeVerificationKeepsEverything() async {
        let store = FakeStore()
        let sync = CalendarSync(store: store)
        let settings = AppSettings()
        settings.calendarSyncOn = true
        await reconcile(sync, settings, isPlus: true)

        // The cached expiry has passed but StoreKit has not answered yet.
        await reconcile(sync, settings, isPlus: false, verified: false, withinGrace: false)

        XCTAssertEqual(store.removeAllCount, 0)
        XCTAssertFalse(store.items.isEmpty)
        XCTAssertTrue(settings.calendarSyncOn)
        XCTAssertEqual(store.replaceCount, 1, "new data is not synced while Plus looks inactive")
    }

    func testOfflineLaunchNeverRemoves() async {
        let store = FakeStore()
        let sync = CalendarSync(store: store)
        let settings = AppSettings()
        settings.calendarSyncOn = true

        // Offline: StoreKit never answers, however far past the cached expiry.
        await reconcile(sync, settings, isPlus: false, verified: false, withinGrace: false)
        await reconcile(sync, settings, isPlus: false, verified: false, withinGrace: false)

        XCTAssertEqual(store.removeAllCount, 0)
        XCTAssertTrue(settings.calendarSyncOn)
    }

    func testBillingRetryNeverRemoves() async {
        let store = FakeStore()
        let sync = CalendarSync(store: store)
        let settings = AppSettings()
        settings.calendarSyncOn = true

        await reconcile(sync, settings, isPlus: false, verified: true, withinGrace: true)

        XCTAssertEqual(store.removeAllCount, 0)
        XCTAssertTrue(settings.calendarSyncOn)
    }

    func testOverlappingTriggersRemoveOnce() async {
        let store = FakeStore()
        let sync = CalendarSync(store: store)
        let settings = AppSettings()
        settings.calendarSyncOn = true

        async let first: Void = reconcile(sync, settings, isPlus: false)
        async let second: Void = reconcile(sync, settings, isPlus: false)
        _ = await (first, second)

        XCTAssertEqual(store.removeAllCount, 1)
        XCTAssertFalse(settings.calendarSyncOn)
    }

    func testLapseWithoutCalendarAccessTurnsOffAndRemovesWhenAccessReturns() async {
        let store = FakeStore()
        store.items = [SyncItem(key: "x", title: "Period", start: anchor, end: anchor, isAllDay: true)]
        store.hasAccess = false
        let sync = CalendarSync(store: store)
        let settings = AppSettings()
        settings.calendarSyncOn = true

        await reconcile(sync, settings, isPlus: false)

        XCTAssertEqual(store.removeAllCount, 0)
        XCTAssertEqual(store.replaceCount, 0)
        XCTAssertFalse(settings.calendarSyncOn, "the switch goes off even without access")
        XCTAssertTrue(settings.calendarSyncPendingRemoval)
        XCTAssertTrue(sync.accessDenied)

        store.hasAccess = true
        await reconcile(sync, settings, isPlus: false)
        XCTAssertEqual(store.removeAllCount, 1)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(settings.calendarSyncPendingRemoval)
    }

    func testPlusWithoutAccessReportsTheMissingAccess() async {
        let store = FakeStore()
        store.hasAccess = false
        let sync = CalendarSync(store: store)
        let settings = AppSettings()
        settings.calendarSyncOn = true

        await reconcile(sync, settings, isPlus: true)

        XCTAssertTrue(sync.accessDenied)
        XCTAssertEqual(sync.lastError, CalendarSync.SyncError.accessDenied.errorDescription)
        XCTAssertTrue(settings.calendarSyncOn)
        XCTAssertEqual(store.replaceCount, 0)

        store.hasAccess = true
        await reconcile(sync, settings, isPlus: true)
        XCTAssertFalse(sync.accessDenied)
        XCTAssertNil(sync.lastError)
    }

    func testFailedRemovalIsRetriedOnTheNextReconcileOnly() async {
        let store = FakeStore()
        store.removeAllError = Failure()
        let sync = CalendarSync(store: store)
        let settings = AppSettings()
        settings.calendarSyncOn = true

        await reconcile(sync, settings, isPlus: false)
        XCTAssertEqual(store.removeAllCount, 1)
        XCTAssertFalse(settings.calendarSyncOn)
        XCTAssertTrue(settings.calendarSyncPendingRemoval, "kept until a removal succeeds")
        XCTAssertEqual(sync.lastError, "The calendar could not be changed.")

        store.removeAllError = nil
        await reconcile(sync, settings, isPlus: false)
        XCTAssertEqual(store.removeAllCount, 2, "retried once on the next trigger")
        XCTAssertFalse(settings.calendarSyncPendingRemoval)
        XCTAssertNil(sync.lastError)

        await reconcile(sync, settings, isPlus: false)
        XCTAssertEqual(store.removeAllCount, 2)
    }

    func testSymbolChangeResyncsWithNewTitles() async {
        let store = FakeStore()
        let sync = CalendarSync(store: store)
        let settings = AppSettings()
        settings.calendarSyncOn = true
        settings.calendarSyncDiscreet = true

        await reconcile(sync, settings, isPlus: true)
        XCTAssertTrue(store.items.contains { $0.key.hasPrefix("period-") && $0.title == "R" })

        settings.calendarSyncSymbolPeriod = "🌙"
        await reconcile(sync, settings, isPlus: true)
        XCTAssertTrue(store.items.contains { $0.key.hasPrefix("period-") && $0.title == "🌙" })
        XCTAssertTrue(store.items.contains { $0.key.hasPrefix("predicted-") && $0.title == "🌙" })
        XCTAssertFalse(store.items.contains { $0.title == "R" })

        settings.calendarSyncSymbolPeriod = "  "
        XCTAssertEqual(settings.calendarSyncSymbols.period, "R", "blank falls back to the default")
    }
}
