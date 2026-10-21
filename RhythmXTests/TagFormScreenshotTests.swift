import SwiftUI
import XCTest
@testable import RhythmX

/// Writes screenshots of the Add Tags sheet (each category body, search with a custom tag) in three theme and
/// appearance pairs, the quick log card and Learn about phases, for a human to compare with the design.
/// Runs only when the test runner has `RHYTHMX_SCREENSHOT_DIR` (pass it as
/// `TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR=<dir>` to xcodebuild).
/// Nothing is written to the stores: the event store is a preview store; mode, theme and Plus cache are restored.
@MainActor
final class TagFormScreenshotTests: XCTestCase {

    private func window() throws -> UIWindow {
        try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow ?? ($0 as? UIWindowScene)?.windows.first }.first)
    }

    private func snap<V: View>(_ view: V, style: UIUserInterfaceStyle, name: String, folder: URL, wait: Double = 1.8) throws {
        let window = try window()
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = style
        let previousStyle = window.overrideUserInterfaceStyle
        window.overrideUserInterfaceStyle = style   // reaches the presented sheet too
        defer { window.overrideUserInterfaceStyle = previousStyle }
        let previous = window.rootViewController
        window.rootViewController = host
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(name).png"))
        host.dismiss(animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        window.rootViewController = previous
    }

    func testWritesAddTagScreenshotsForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["RHYTHMX_SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR to write review screenshots")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let settings = AppSettings()
        let saved = (settings.trackingMode, settings.themeID,
                     AppGroup.defaults.object(forKey: PersistenceKeys.plusExpiry) as? Date)
        defer {
            settings.trackingMode = saved.0
            settings.themeID = saved.1
            AppGroup.defaults.set(saved.2, forKey: PersistenceKeys.plusExpiry)
        }
        // Plus themes are drawn only while Plus is active.
        AppGroup.defaults.set(Date().addingTimeInterval(86_400 * 30), forKey: PersistenceKeys.plusExpiry)

        let calendar = Calendar.current
        let today = Date()
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))! }
        func p(_ c: TagCategory, _ v: String) -> TagPick { TagPick(category: c, value: v) }

        func stores(for mode: TrackingMode) -> (EventStore, ArchivedDataStore, HealthSync) {
            let events = EventStore(preview: true)
            var generated = CycleGenerator.events(startDate: day(-25), cycleLength: 28)   // day 26, luteal
            generated[3].tags = "Symptom:Cramps, Mood:Calm"
            generated[22].tags = "Exercise:Yoga, Dietary:Sweet Craving"
            generated[24].tags = "Symptom:Bloating, Mood:Calm"
            if mode == .menopause {
                generated = [Event(eventType: .follicular, date: day(-1), note: "",
                                   tags: "Menopause:Hot Flashes, Menopause:Poor Sleep", mode: .menopause),
                             Event(eventType: .follicular, date: day(0), note: "",
                                   tags: "Menopause:Hot Flashes", mode: .menopause)]
            }
            events.events = generated
            let archive = ArchivedDataStore()
            let past = CycleGenerator.events(startDate: day(-53), cycleLength: 28).map { e -> Event in
                var e = e
                if e.eventType == .luteal { e.tags = "Symptom:Bloating, Symptom:Breast Tenderness" }
                return e
            }
            archive.archivedBlocks = [ArchivedDataBlock(date: day(-53), groupedEvents: Dictionary(grouping: past, by: \.eventType)
                .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) })]
            let health = HealthSync()
            health.importedTemperatures = [PlanningInsights.TempPoint(date: day(0), value: 97.72)]
            return (events, archive, health)
        }

        var cycle = TagSelection()
        cycle.set(p(.symptom, "Bloating"), level: .medium)
        cycle.set(p(.symptom, "Breast Tenderness"), level: .light)
        cycle.add(p(.mood, "Calm"))
        var mood = cycle
        mood.add(p(.mood, "Low Energy"))
        var planning = TagSelection()
        planning.add(p(.planning, "Ovulation Test Positive"))
        planning.add(p(.planning, "Intercourse"))
        var menopause = TagSelection()
        for _ in 0..<3 { menopause.increment(p(.menopause, "Hot Flashes")) }
        menopause.increment(p(.menopause, "Night Sweats"))
        menopause.set(p(.menopause, "Poor Sleep"), level: .medium)
        menopause.set(p(.menopause, "Brain Fog"), level: .light)

        let sheets: [(String, TrackingMode, TagCategory, TagSelection, String)] = [
            ("tag-a", .cycle, .symptom, cycle, ""),
            ("tag-mood", .cycle, .mood, mood, ""),
            ("tag-planning", .planning, .planning, planning, ""),
            ("tag-menopause", .menopause, .menopause, menopause, ""),
            ("tag-basal", .planning, .basalTemp, TagSelection(), ""),
            ("tag-search", .cycle, .symptom, TagSelection(), "Sore throat"),
        ]
        let pairs: [(String, String, UIUserInterfaceStyle)] = [
            ("blush-light", AppTheme.blush.id, .light),
            ("blush-dark", AppTheme.blush.id, .dark),
            ("eclipse-dark", AppTheme.eclipse.id, .dark),
        ]
        for (name, mode, category, picks, query) in sheets {
            settings.trackingMode = mode
            let (events, archive, health) = stores(for: mode)
            for (suffix, themeID, style) in pairs {
                settings.themeID = themeID
                let root = Color.clear
                    .themedPage()
                    .sheet(isPresented: .constant(true)) {
                        TagFormView(initialDate: today, initialCategory: category, initialSelection: picks, initialQuery: query)
                            .environmentObject(events)
                            .environmentObject(archive)
                            .environmentObject(settings)
                            .environmentObject(health)
                    }
                    .environment(\.auraPhase, mode == .menopause ? nil : .luteal)
                    .environmentObject(settings)
                try snap(root, style: style, name: "\(name)--\(suffix)", folder: folder)
            }
        }

        // The quick log card over Today, every pair, Cycle mode, Bloating picked.
        settings.trackingMode = .cycle
        let (events, archive, health) = stores(for: .cycle)
        var quick = QuickLogSelection()
        quick.toggle(p(.symptom, "Bloating"))
        for (suffix, themeID, style) in pairs + [("blue-dark", AppTheme.blueMoon.id, .dark)] {
            settings.themeID = themeID
            let facts = InsightFacts.make(events: events.events, archivedBlocks: [], mode: .cycle, today: today)
            let root = TodayView(now: today, fixedInsights: TemplateInsightWriter().insights(for: facts))
                .sheet(isPresented: .constant(true)) {
                    QuickLogCardView(now: today, initialSelection: quick)
                        .environmentObject(events).environmentObject(archive).environmentObject(settings)
                }
                .environment(\.auraPhase, .luteal)
                .environmentObject(events).environmentObject(archive).environmentObject(settings)
                .environmentObject(FertileStore()).environmentObject(health)
            try snap(root, style: style, name: "quicklog--\(suffix)", folder: folder)
        }
        settings.themeID = AppTheme.blush.id

        // Learn about phases, Planning mode.
        settings.trackingMode = .planning
        try snap(NavigationStack { PhasesFactsView() }.environmentObject(settings), style: .light,
                 name: "learn-planning-light", folder: folder)
    }
}
