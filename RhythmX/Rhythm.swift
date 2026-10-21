//
//  AppEntry.swift
//

import SwiftUI

@main
struct AppEntry: App {
    @StateObject var myEvents          = EventStore(preview: false)
    @StateObject var archivedDataStore = ArchivedDataStore()
    @StateObject var appSettings       = AppSettings()
    @StateObject var fertileStore      = FertileStore()
    // Under XCTest the host app stays off the transaction queue, so PurchaseStoreTests own every test purchase.
    @StateObject var purchaseStore     = PurchaseStore(listensForUpdates: !AppEntry.isRunningTests)
    @StateObject var healthSync        = HealthSync()
    @StateObject var calendarSync      = CalendarSync()

    @AppStorage("didFinishOnboarding") var didFinishOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSplash = true
    @State private var incomingBackup: IncomingBackup?

    init() {
        LegacySnapshot.writeIfNeeded()   // raw pre-migration copy, before any store loads or migration runs
        AppGroup.migrateIfNeeded()
        // Settings > "Default mode on launch": a fixed mode replaces the remembered one before any view
        // reads it. AppSettings is UserDefaults-backed, so this instance and the @StateObject agree.
        // The rule itself is covered by ModeFilterTests.testLaunchModeLastKeepsStoredMode and testLaunchModeFixedOverrides.
        AppSettings().applyLaunchMode()
        // Turns the raw copy into a restorable pre-update safety copy (once; retried while it fails),
        // then applies the retention rules to every safety copy.
        SafetyCopies.convertLegacySnapshotIfNeeded(
            settings: AppSettings().settingsSnapshot(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        )
        SafetyCopies.prune()
        BackupViewModel.clearExports()   // a backup export left over from a previous run
        NotificationTapRouter.install()  // notification taps open the quick log or the Tags tab (StartTabView)
        // First launch of the build with Daily insights: tag reminders and the daily check-in are cancelled
        // and their stored settings deleted, once.
        if !AppEntry.isRunningTests {
            Task { await NotificationMigration.runIfNeeded() }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                content
                if showSplash {
                    SplashView { withAnimation(.easeOut(duration: 0.45)) { showSplash = false } }
                        .environmentObject(appSettings)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            // "Open with RhythmX" from Files, AirDrop or Mail. RestoreView reads the file with
            // security-scoped access (BackupViewModel.loadFile).
            // A locked Plus widget ("Tap to unlock") opens the paywall once onboarding is done; during
            // onboarding the link is dropped (`opensPaywall`).
            .onOpenURL { url in
                if Self.opensPaywall(url, onboardingFinished: didFinishOnboarding) {
                    purchaseStore.isPaywallPresented = true
                    return
                }
                guard url.isFileURL, url.pathExtension.lowercased() == BackupFile.fileExtension else { return }
                incomingBackup = IncomingBackup(url: url)
            }
            .sheet(item: $incomingBackup) { item in
                RestoreSheet(url: item.url)
                    .environmentObject(myEvents)
                    .environmentObject(archivedDataStore)
                    .environmentObject(appSettings)
            }
            // The single paywall sheet. Settings sets the same flag, so the two can never collide.
            .sheet(isPresented: $purchaseStore.isPaywallPresented) {
                PaywallView().environmentObject(purchaseStore)
            }
            .onChange(of: scenePhase) { _, phase in
                // No exported backup file lingers in the temporary directory once the app is in the background.
                if phase == .background { BackupViewModel.clearExports() }
                // A tag logged from the Quick Log widget while the app was away lands in the shared store.
                if phase == .active {
                    myEvents.reloadFromDiskIfChanged()
                    // Fresh Health readings (and any period day logged since) each time the app comes back, and
                    // the Apple Calendar brought up to date while sync is on. Plus is refreshed from StoreKit
                    // first, so a renewal the cache has not seen yet never clears the calendar.
                    if !AppEntry.isRunningTests {
                        Task {
                            await healthSync.refresh(events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks,
                                                     settings: appSettings)
                            await purchaseStore.refreshEntitlements()
                            await reconcileCalendar()
                        }
                        // The next Daily insights note is written each time the app comes back (when it is on).
                        if appSettings.dailyInsightsOn { DailyInsightsCoordinator.shared.update(write: true) }
                    }
                }
            }
            // Products, unfinished purchases and the Plus cache for the widgets, once per launch.
            .task {
                guard !AppEntry.isRunningTests else { return }
                healthSync.bind(eventStore: myEvents, archivedDataStore: archivedDataStore, settings: appSettings)
                calendarSync.bind(eventStore: myEvents, archivedDataStore: archivedDataStore, fertileStore: fertileStore,
                                  settings: appSettings, purchaseStore: purchaseStore)
                await purchaseStore.load()
                // Launch, after StoreKit has answered (`load` ends with `refreshEntitlements`): sync, or on a
                // confirmed lapse past grace remove the app's events once and turn the switch off.
                await reconcileCalendar()
            }
        }
        // Daily insights: the background app refresh requested about three hours before the chosen time
        // (`DailyInsightsBackground`). SwiftUI registers the identifier at launch and cancels the task when its
        // time runs out; the template note already scheduled then stays.
        .backgroundTask(.appRefresh(DailyInsightsBackground.taskIdentifier)) {
            await DailyInsightsBackground.handle()
        }
    }

    /// Apple Calendar sync after launch, foreground or an entitlement change (`CalendarSyncPolicy`).
    @MainActor
    private func reconcileCalendar() async {
        await calendarSync.reconcile(events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks,
                                     overrides: fertileStore.overrides, settings: appSettings,
                                     isPlus: purchaseStore.isPlus,
                                     verified: purchaseStore.entitlementVerifiedThisSession,
                                     withinGrace: purchaseStore.isWithinPlusGrace)
    }

    static let isRunningTests: Bool =
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Whether `url` opens the paywall: the widget's `rhythmx://paywall` link, and only once onboarding is
    /// finished. The paywall has no place over the onboarding pages, so an earlier tap is dropped, not queued.
    static func opensPaywall(_ url: URL, onboardingFinished: Bool) -> Bool {
        onboardingFinished && PlusWidgetState.isPaywallLink(url)
    }

    @ViewBuilder
    private var content: some View {
        themedContent.tint(DS.Color.accent)
    }

    @ViewBuilder
    private var themedContent: some View {
        Group {
            if didFinishOnboarding {
                StartTabView()
                    .environmentObject(myEvents)
                    .environmentObject(archivedDataStore)
                    .environmentObject(appSettings)
                    .environmentObject(fertileStore)
                    .environmentObject(purchaseStore)
                    .environmentObject(healthSync)
                    .environmentObject(calendarSync)
            } else {
                OnboardingView()
                    .environmentObject(myEvents)
                    .environmentObject(archivedDataStore)
                    .environmentObject(appSettings)
                    .environmentObject(purchaseStore)
                    .environmentObject(healthSync)
            }
        }
    }
}
