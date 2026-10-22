import SwiftUI
import StoreKitTest
import XCTest
@testable import RhythmX

/// Writes screenshots of Today (Cycle, Planning, Menopause) in four theme and appearance pairs, plus the splash and
/// the first onboarding page, for a human to compare with the design. Runs only when the test runner has
/// `RHYTHMX_SCREENSHOT_DIR` (pass it as `TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR=<dir>` to xcodebuild).
/// Nothing is written to the event stores (preview stores); the mode, theme and Plus cache are restored.
@MainActor
final class TodayScreenshotTests: XCTestCase {

    private func window() throws -> UIWindow {
        try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow ?? ($0 as? UIWindowScene)?.windows.first }.first)
    }

    private func snap<V: View>(_ view: V, style: UIUserInterfaceStyle, name: String, folder: URL, wait: Double = 1.6) throws {
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
        window.rootViewController = previous
    }

    func testWritesTodayScreenshotsForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["RHYTHMX_SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR to write review screenshots")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let settings = AppSettings()
        let saved = (settings.trackingMode, settings.themeID, settings.greetingStyleRaw,
                     AppGroup.defaults.object(forKey: PersistenceKeys.plusExpiry) as? Date)
        defer {
            settings.trackingMode = saved.0
            settings.themeID = saved.1
            settings.greetingStyleRaw = saved.2
            AppGroup.defaults.set(saved.3, forKey: PersistenceKeys.plusExpiry)
        }
        // Plus themes are drawn only while Plus is active.
        AppGroup.defaults.set(Date().addingTimeInterval(86_400 * 30), forKey: PersistenceKeys.plusExpiry)
        settings.greetingStyle = .greeting

        let calendar = Calendar.current
        var evening = calendar.dateComponents([.year, .month, .day], from: Date())
        evening.hour = 19
        let now = calendar.date(from: evening)!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))! }

        func store(for mode: TrackingMode) -> EventStore {
            let events = EventStore(preview: true)
            switch mode {
            case .cycle:
                var generated = CycleGenerator.events(startDate: day(-25), cycleLength: 28)   // day 26, luteal
                generated[3].tags = "Symptom:Cramps, Mood:Calm"
                generated[24].tags = "Symptom:Bloating, Dietary:Sweet Craving"
                events.events = generated
            case .planning:
                events.events = CycleGenerator.events(startDate: day(-5), cycleLength: 28)     // day 6, window soon
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

        let pairs: [(String, String, UIUserInterfaceStyle)] = [
            ("blush-light", AppTheme.blush.id, .light),
            ("blush-dark", AppTheme.blush.id, .dark),
            ("eclipse-dark", AppTheme.eclipse.id, .dark),
            ("blue-dark", AppTheme.blueMoon.id, .dark),
        ]
        for mode in TrackingMode.allCases {
            settings.trackingMode = mode
            let events = store(for: mode)
            let archive = ArchivedDataStore()
            let facts = InsightFacts.make(events: events.events, archivedBlocks: [], mode: mode, today: now)
            let insights = TemplateInsightWriter().insights(for: facts)
            for (suffix, themeID, style) in pairs {
                settings.themeID = themeID
                let root = TabView {
                    TodayView(now: now, fixedInsights: insights)
                        .tabItem { Label("Today", systemImage: "moonphase.first.quarter") }
                    Color.clear.tabItem { Label("Calendar", systemImage: "calendar") }
                    Color.clear.tabItem { Label("Tags", systemImage: "tag.fill") }
                    Color.clear.tabItem { Label("Cycles", systemImage: "moon.circle") }
                    Color.clear.tabItem { Label("Settings", systemImage: "gearshape") }
                }
                .tint(DS.Color.accent)
                .environment(\.auraPhase, mode == .menopause ? nil
                             : PhaseWidgetSnapshot.make(events: events.events, archived: [], today: now).phase)
                .environmentObject(events)
                .environmentObject(archive)
                .environmentObject(settings)
                .environmentObject(FertileStore())
                .environmentObject(HealthSync())
                try snap(root, style: style, name: "today-\(mode.rawValue)--\(suffix)", folder: folder)
            }
        }

        // Accessibility text size, Cycle, Blush light.
        settings.trackingMode = .cycle
        settings.themeID = AppTheme.blush.id
        let events = store(for: .cycle)
        let insights = TemplateInsightWriter().insights(for: InsightFacts.make(events: events.events, archivedBlocks: [],
                                                                                 mode: .cycle, today: now))
        let large = TodayView(now: now, fixedInsights: insights)
            .environment(\.dynamicTypeSize, .accessibility2)
            .environmentObject(events).environmentObject(ArchivedDataStore()).environmentObject(settings)
            .environmentObject(FertileStore()).environmentObject(HealthSync())
        try snap(large, style: .light, name: "today-cycle--blush-light-ax2", folder: folder)

        // The Calendar tab over the (still) aura: it must stay readable.
        for (suffix, themeID, style) in [("blush-light", AppTheme.blush.id, UIUserInterfaceStyle.light),
                                         ("eclipse-dark", AppTheme.eclipse.id, .dark)] {
            settings.themeID = themeID
            let calendarView = EventsCalendarView()
                .environment(\.auraPhase, .luteal)
                .environmentObject(events).environmentObject(ArchivedDataStore()).environmentObject(settings)
                .environmentObject(FertileStore()).environmentObject(PurchaseStore(listensForUpdates: false))
                .environmentObject(CalendarSync())
            try snap(calendarView, style: style, name: "calendar--\(suffix)", folder: folder)
        }
        settings.themeID = AppTheme.blush.id

        // Splash (mid sequence) and the first onboarding page, Blush light: both draw the dark night scene.
        try snap(SplashView(onFinish: {}).environmentObject(settings), style: .light, name: "splash--blush-light",
                 folder: folder, wait: 1.4)
        try snap(OnboardingView().environmentObject(EventStore(preview: true)).environmentObject(settings)
                    .environmentObject(ArchivedDataStore()).environmentObject(PurchaseStore(listensForUpdates: false))
                    .environmentObject(HealthSync()),
                 style: .light, name: "onboarding-1--blush-light", folder: folder)
        settings.themeID = AppTheme.eclipse.id
        try snap(SplashView(onFinish: {}).environmentObject(settings), style: .dark, name: "splash--eclipse-dark",
                 folder: folder, wait: 1.4)
    }

    /// The paywall with real StoreKit products (local `RhythmX.storekit`), for App Store Connect review.
    func testWritesPaywallScreenshotForReview() async throws {
        guard let dir = ProcessInfo.processInfo.environment["RHYTHMX_SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR to write review screenshots")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try XCTUnwrap(Bundle(for: TodayScreenshotTests.self).url(forResource: "RhythmX", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        let store = PurchaseStore(listensForUpdates: false)
        await store.loadProducts()
        let settings = AppSettings()
        try snap(PaywallView().environmentObject(store).environmentObject(settings), style: .light,
                 name: "paywall--blush-light", folder: folder, wait: 2)
        try snap(PaywallView(showsDayPass: true).environmentObject(store).environmentObject(settings), style: .light,
                 name: "paywall-daypass--blush-light", folder: folder, wait: 2)
    }
}
