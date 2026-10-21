import SwiftUI
import XCTest
@testable import RhythmX

/// Writes screenshots of the Notifications page (on, off, denied, accessibility size, the info text), the Share
/// screen with its partner view, every share card PNG and Settings with its info circles, in four theme and
/// appearance pairs, for a human to compare with the design. Runs only when the test runner has
/// `RHYTHMX_SCREENSHOT_DIR` (pass it as `TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR=<dir>` to xcodebuild).
/// Event stores are preview stores; every setting touched is restored.
@MainActor
final class ShareNotificationsScreenshotTests: XCTestCase {

    private func window() throws -> UIWindow {
        try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow ?? ($0 as? UIWindowScene)?.windows.first }.first)
    }

    private func snap<V: View>(_ view: V, style: UIUserInterfaceStyle, name: String, folder: URL, wait: Double = 1.4) throws {
        let window = try window()
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = style
        let previous = window.rootViewController
        window.rootViewController = host
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(name).png"))
        // A sheet presented by the screen goes with it.
        host.presentedViewController?.dismiss(animated: false)
        window.rootViewController = previous
    }

    func testWritesShareAndNotificationScreenshotsForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["RHYTHMX_SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR to write review screenshots")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let settings = AppSettings()
        let saved = (settings.trackingMode, settings.themeID, settings.notificationsEnabled, settings.fertileStartOn,
                     settings.fertileOvulationOn, settings.dailyInsightsOn, settings.dailyInsightsHour,
                     settings.dailyInsightsMinute, settings.dailyInsightsDiscreet, settings.weeklyCheckInData,
                     settings.sharerName, AppGroup.defaults.object(forKey: PersistenceKeys.plusExpiry) as? Date)
        defer {
            settings.trackingMode = saved.0
            settings.themeID = saved.1
            settings.notificationsEnabled = saved.2
            settings.fertileStartOn = saved.3
            settings.fertileOvulationOn = saved.4
            settings.dailyInsightsOn = saved.5
            settings.dailyInsightsHour = saved.6
            settings.dailyInsightsMinute = saved.7
            settings.dailyInsightsDiscreet = saved.8
            settings.weeklyCheckInData = saved.9
            settings.sharerName = saved.10
            AppGroup.defaults.set(saved.11, forKey: PersistenceKeys.plusExpiry)
        }
        AppGroup.defaults.set(Date().addingTimeInterval(86_400 * 30), forKey: PersistenceKeys.plusExpiry)

        let calendar = Calendar.current
        var evening = calendar.dateComponents([.year, .month, .day], from: Date())
        evening.hour = 19
        let now = calendar.date(from: evening)!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))! }

        func store(for mode: TrackingMode) -> EventStore {
            let events = EventStore(preview: true)
            switch mode {
            case .cycle:
                events.events = CycleGenerator.events(startDate: day(-25), cycleLength: 28)   // day 26, luteal
            case .planning:
                events.events = CycleGenerator.events(startDate: day(-5), cycleLength: 28)    // day 6, window soon
            case .menopause:
                events.events = CycleGenerator.events(startDate: day(-60), cycleLength: 28).prefix(5).map { $0 }
                for back in 0..<14 {
                    let flashes = back < 7 ? (back % 3 == 0 ? 2 : 1) : 2
                    events.events.append(Event(eventType: .follicular, date: day(-back), note: "",
                                               tags: Array(repeating: "Menopause:Hot Flashes", count: flashes).joined(separator: ", "),
                                               mode: .menopause))
                }
            }
            return events
        }

        func setNotifications(on: Bool) {
            settings.notificationsEnabled = on
            settings.fertileStartOn = false
            settings.fertileOvulationOn = on
            settings.dailyInsightsOn = on
            settings.dailyInsightsHour = 20
            settings.dailyInsightsMinute = 0
            settings.dailyInsightsDiscreet = false
            var weekly = CheckInSetting.defaultWeekly
            weekly.isOn = on
            settings.weeklyCheckIn = weekly
        }

        func notifications(_ events: EventStore, denied: Bool) -> some View {
            NavigationStack {
                NotificationsSettingsView(now: now, forcedPermissionDenied: denied)
            }
            .environment(\.auraPhase, .luteal)
            .environmentObject(events).environmentObject(ArchivedDataStore())
            .environmentObject(settings).environmentObject(FertileStore())
        }

        let pairs: [(String, String, UIUserInterfaceStyle)] = [
            ("blush-light", AppTheme.blush.id, .light),
            ("blush-dark", AppTheme.blush.id, .dark),
            ("eclipse-dark", AppTheme.eclipse.id, .dark),
            ("blue-dark", AppTheme.blueMoon.id, .dark),
        ]

        settings.trackingMode = .cycle
        settings.sharerName = ""
        let cycle = store(for: .cycle)

        for (suffix, themeID, style) in pairs {
            settings.themeID = themeID

            // Notifications: on, off, denied.
            setNotifications(on: true)
            try snap(notifications(cycle, denied: false), style: style, name: "notif-on--\(suffix)", folder: folder)
            setNotifications(on: false)
            try snap(notifications(cycle, denied: false), style: style, name: "notif-off--\(suffix)", folder: folder)
            setNotifications(on: true)
            try snap(notifications(cycle, denied: true), style: style, name: "notif-denied--\(suffix)", folder: folder)

            // Share, Cycle mode.
            let share = NavigationStack { ShareRhythmView(now: now) }
                .environment(\.auraPhase, .luteal)
                .environmentObject(cycle).environmentObject(ArchivedDataStore())
                .environmentObject(FertileStore()).environmentObject(settings)
            try snap(share, style: style, name: "share--\(suffix)", folder: folder, wait: 2)

            // Settings with the info circles.
            let settingsView = SettingsView()
                .environment(\.auraPhase, .luteal)
                .environmentObject(cycle).environmentObject(settings).environmentObject(ArchivedDataStore())
                .environmentObject(FertileStore()).environmentObject(PurchaseStore(listensForUpdates: false))
                .environmentObject(HealthSync()).environmentObject(CalendarSync())
            try snap(settingsView, style: style, name: "settings--\(suffix)", folder: folder)

            // Every card, as the PNG that is shared.
            for mode in TrackingMode.allCases {
                let events = store(for: mode)
                let facts = InsightFacts.make(events: events.events, archivedBlocks: [], mode: mode, today: now)
                let snapshot = PhaseWidgetSnapshot.make(events: events.events, archived: [], today: now)
                let input = ShareCardInput(mode: mode, insights: TemplateInsightWriter().insights(for: facts), facts: facts,
                                           fertileToday: snapshot.isFertileToday, fertileStartsIn: snapshot.fertileStartsIn,
                                           sharerName: mode == .cycle ? "Ana" : "")
                let theme = try XCTUnwrap(AppTheme.named(themeID))
                let palette = style == .dark ? theme.dark : theme.light
                for card in ShareCardModel.cards(for: input) {
                    let png = try XCTUnwrap(ShareCardView.pngData(for: card, palette: palette, isDark: style == .dark))
                    let image = try XCTUnwrap(UIImage(data: png))
                    XCTAssertEqual(image.size.width * image.scale, 1080, card.id)
                    XCTAssertEqual(image.size.height * image.scale, 1350, card.id)
                    try png.write(to: folder.appendingPathComponent("card-\(mode.rawValue)-\(card.id)--\(suffix).png"))
                }
            }
        }

        // Blush light extras: Planning and Menopause share screens, the partner view, discreet preview,
        // accessibility size and the info text.
        settings.themeID = AppTheme.blush.id
        for mode in [TrackingMode.planning, .menopause] {
            settings.trackingMode = mode
            let events = store(for: mode)
            let share = NavigationStack { ShareRhythmView(now: now) }
                .environment(\.auraPhase, mode == .menopause ? nil : .follicular)
                .environmentObject(events).environmentObject(ArchivedDataStore())
                .environmentObject(FertileStore()).environmentObject(settings)
            try snap(share, style: .light, name: "share-\(mode.rawValue)--blush-light", folder: folder, wait: 2)
        }
        settings.trackingMode = .cycle
        let partner = NavigationStack { ShareRhythmView(now: now, showsPartnerViewInitially: true) }
            .environment(\.auraPhase, .luteal)
            .environmentObject(cycle).environmentObject(ArchivedDataStore())
            .environmentObject(FertileStore()).environmentObject(settings)
        try snap(partner, style: .light, name: "share-partner--blush-light", folder: folder, wait: 2.5)

        setNotifications(on: true)
        settings.dailyInsightsDiscreet = true
        try snap(notifications(cycle, denied: false), style: .light, name: "notif-discreet--blush-light", folder: folder)
        settings.dailyInsightsDiscreet = false

        try snap(notifications(cycle, denied: false).environment(\.dynamicTypeSize, .accessibility2),
                 style: .light, name: "notif-ax--blush-light", folder: folder)

        // The info text as the popover and as the accessibility sheet show it.
        let popover = ZStack {
            Color.black.opacity(0.08).ignoresSafeArea()
            InfoPopoverContent(topic: InfoCopy.dailyInsights)
                .frame(width: 320)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS.Color.cardBackground))
        }
        .themedPage()
        try snap(popover, style: .light, name: "notif-info-popover--blush-light", folder: folder, wait: 0.8)
        try snap(InfoSheet(topic: InfoCopy.dailyInsights, done: {}).environment(\.dynamicTypeSize, .accessibility2),
                 style: .light, name: "notif-info-sheet-ax--blush-light", folder: folder, wait: 0.8)
    }
}
