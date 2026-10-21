import SwiftUI
import XCTest
@testable import RhythmX

/// Writes screenshots of every onboarding page and of the daily insight pull-up at fixed animation moments
/// (rest, mid-reveal, drawing, complete) in Cycle, Planning and Menopause, in four theme and appearance pairs,
/// for a human to compare with the design. Runs only when the test runner has `RHYTHMX_SCREENSHOT_DIR`
/// (pass it as `TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR=<dir>` to xcodebuild). Preview stores only; the mode,
/// theme, greeting and Plus cache are restored.
@MainActor
final class OnboardingInsightScreenshotTests: XCTestCase {

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
        window.rootViewController = previous
    }

    func testWritesOnboardingAndInsightScreenshotsForReview() throws {
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
        AppGroup.defaults.set(Date().addingTimeInterval(86_400 * 30), forKey: PersistenceKeys.plusExpiry)
        settings.greetingStyle = .greeting

        let calendar = Calendar.current
        var evening = calendar.dateComponents([.year, .month, .day], from: Date())
        evening.hour = 19
        let now = calendar.date(from: evening)!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))! }

        let pairs: [(String, String, UIUserInterfaceStyle)] = [
            ("blush-light", AppTheme.blush.id, .light),
            ("blush-dark", AppTheme.blush.id, .dark),
            ("eclipse-dark", AppTheme.eclipse.id, .dark),
            ("blue-dark", AppTheme.blueMoon.id, .dark),
        ]

        // Onboarding, every page, on an empty phone.
        settings.trackingMode = .cycle
        for (suffix, themeID, style) in pairs {
            settings.themeID = themeID
            for page in OnboardingPage.allCases {
                let view = OnboardingView(initialPage: page, now: now)
                    .environmentObject(EventStore(preview: true)).environmentObject(ArchivedDataStore())
                    .environmentObject(settings).environmentObject(PurchaseStore(listensForUpdates: false))
                try snap(view, style: style, name: "onb-\(page.index + 1)--\(suffix)", folder: folder,
                         wait: page == .phases ? 2.2 : 1.4)
            }
        }
        settings.themeID = AppTheme.blush.id
        let large = OnboardingView(initialPage: .makeItYours, now: now)
            .environment(\.dynamicTypeSize, .accessibility2)
            .environmentObject(EventStore(preview: true)).environmentObject(ArchivedDataStore())
            .environmentObject(settings).environmentObject(PurchaseStore(listensForUpdates: false))
        try snap(large, style: .light, name: "onb-5--blush-light-ax2", folder: folder)

        // The pull-up.
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
                for back in 0..<50 {
                    let flashes = back % 4 == 0 ? 3 : (back % 3 == 0 ? 0 : 1)
                    guard flashes > 0 else { continue }
                    events.events.append(Event(eventType: .follicular, date: day(-back), note: "",
                                               tags: Array(repeating: "Menopause:Hot Flashes", count: flashes).joined(separator: ", "),
                                               mode: .menopause))
                }
            }
            return events
        }

        let moments: [(String, Double)] = [("rest", 0), ("reveal", 0.22), ("draw", 0.62), ("complete", 1)]
        for mode in TrackingMode.allCases {
            settings.trackingMode = mode
            let events = store(for: mode)
            let facts = InsightFacts.make(events: events.events, archivedBlocks: [], mode: mode, today: now)
            var insights = TemplateInsightWriter().insights(for: facts)
            let snapshot = PhaseWidgetSnapshot.make(events: events.events, archived: [], today: now)
            let tile: DailyInsightTile
            switch mode {
            case .cycle:
                tile = DailyInsightTile(kind: .pattern, title: "Your pattern",
                                        body: "Sweet cravings came on day 24 to 27 in 4 of your last 5 cycles. Today is day 26.",
                                        symbols: ["chart.bar"], isAI: true)
                insights.tiles.append(tile)
            case .planning:
                tile = insights.tile(.fertile) ?? insights.tiles[0]
            case .menopause:
                tile = insights.tile(.menopauseSymptoms) ?? insights.tiles[0]
            }
            let weeks = MenopauseInsights.make(events: events.events, today: now).hotFlashesPerWeek
            let model = TodayView.detailModel(tile: tile, mode: mode, events: events.events, archivedBlocks: [],
                                              insights: insights, facts: facts, snapshot: snapshot,
                                              hotFlashWeeks: weeks, sharerName: "", today: now)
            let auraPhase = mode == .menopause ? nil : snapshot.phase
            for (suffix, themeID, style) in pairs {
                settings.themeID = themeID
                for (moment, progress) in moments {
                    let root = ZStack(alignment: .top) {
                        TodayView(now: now, fixedInsights: insights)
                        Color.black.opacity(0.3).ignoresSafeArea()
                        DailyInsightDetailView(model: model, fixedProgress: progress)
                            .background(InsightSheetBackground(phase: auraPhase))
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38, style: .continuous))
                            .padding(.top, 56)
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .environment(\.auraPhase, auraPhase)
                    .environmentObject(events).environmentObject(ArchivedDataStore()).environmentObject(settings)
                    .environmentObject(FertileStore()).environmentObject(HealthSync())
                    try snap(root, style: style, name: "insight-\(mode.rawValue)-\(moment)--\(suffix)", folder: folder, wait: 1.0)
                }
            }
        }
    }
}
