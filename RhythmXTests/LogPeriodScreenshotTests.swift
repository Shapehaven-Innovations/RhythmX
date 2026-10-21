import SwiftUI
import XCTest
@testable import RhythmX

/// Writes screenshots of the Log Period sheet (today by default, and a past day early in a cycle where the start
/// can move) and of the Cycles tab, for a human to compare with the design. Runs only when the test runner has
/// `RHYTHMX_SCREENSHOT_DIR` (pass it as `TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR=<dir>` to xcodebuild). Each screen
/// is also held for a moment with a `<name>.ready` marker in that folder, so a watcher outside the simulator can
/// take a device screenshot and answer with `<name>.done`. Nothing is written to the stores (preview stores,
/// blocks set in memory); the mode and theme are restored.
@MainActor
final class LogPeriodScreenshotTests: XCTestCase {

    private func window() throws -> UIWindow {
        try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow ?? ($0 as? UIWindowScene)?.windows.first }.first)
    }

    private func snap<V: View>(_ view: V, style: UIUserInterfaceStyle, name: String, folder: URL, wait: Double = 2.0) throws {
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
        hold(name, folder: folder)
        host.dismiss(animated: false)
        window.rootViewController = previous
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }

    /// Leaves the screen up until a watcher answers, or for eight seconds.
    private func hold(_ name: String, folder: URL) {
        let ready = folder.appendingPathComponent("\(name).ready")
        let done = folder.appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        let deadline = Date().addingTimeInterval(8)
        while !FileManager.default.fileExists(atPath: done.path) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
    }

    func testWritesLogPeriodScreenshotsForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["RHYTHMX_SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR to write review screenshots")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let settings = AppSettings()
        let saved = (settings.trackingMode, settings.themeID)
        defer {
            settings.trackingMode = saved.0
            settings.themeID = saved.1
        }
        settings.trackingMode = .cycle
        settings.themeID = AppTheme.blush.id

        let calendar = Calendar.current
        var evening = calendar.dateComponents([.year, .month, .day], from: Date())
        evening.hour = 19
        let now = calendar.date(from: evening)!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))! }

        /// A current cycle starting `back` days ago, with a couple of tags, plus two finished cycles before it.
        func stores(back: Int) -> (EventStore, ArchivedDataStore) {
            let events = EventStore(preview: true)
            var generated = CycleGenerator.events(startDate: day(-back), cycleLength: 28)
            generated[min(1, generated.count - 1)].tags = "Symptom:Cramps, Mood:Calm"
            generated[min(back, generated.count - 1)].tags = "Symptom:Bloating"
            events.events = generated
            let archive = ArchivedDataStore()
            archive.archivedBlocks = [1, 2].map { n in
                let start = day(-back - 29 * n)
                var cycle = CycleGenerator.events(startDate: start, cycleLength: 29)
                cycle[2].tags = "Symptom:Cramps"
                cycle[20].tags = "Mood:Irritable, Dietary:Sweet Craving"
                return ArchivedDataBlock(date: day(-back - 29 * (n - 1)),
                                         groupedEvents: Dictionary(grouping: cycle, by: \.eventType)
                                            .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) })
            }
            return (events, archive)
        }

        func sheetOverToday(events: EventStore, archive: ArchivedDataStore, start: Date?) -> some View {
            let insights = TemplateInsightWriter().insights(for: InsightFacts.make(events: events.events, archivedBlocks: archive.archivedBlocks,
                                                                                     mode: .cycle, today: now))
            return TabView {
                TodayView(now: now, fixedInsights: insights)
                    .tabItem { Label("Today", systemImage: "moonphase.first.quarter") }
                Color.clear.tabItem { Label("Calendar", systemImage: "calendar") }
                Color.clear.tabItem { Label("Tags", systemImage: "tag.fill") }
                Color.clear.tabItem { Label("Cycles", systemImage: "moon.circle") }
                Color.clear.tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .tint(DS.Color.accent)
            .sheet(isPresented: .constant(true)) { LogPeriodSheet(now: now, initialStart: start) }
            .environment(\.auraPhase, PhaseWidgetSnapshot.make(events: events.events, archived: archive.archivedBlocks, today: now).phase)
            .environmentObject(events)
            .environmentObject(archive)
            .environmentObject(settings)
            .environmentObject(FertileStore())
            .environmentObject(HealthSync())
        }

        // Day 26: the sheet opens on today and offers a new cycle.
        let (late, lateArchive) = stores(back: 25)
        try snap(sheetOverToday(events: late, archive: lateArchive, start: nil), style: .light,
                 name: "log-period-sheet--today--blush-light", folder: folder)
        try snap(sheetOverToday(events: late, archive: lateArchive, start: nil), style: .dark,
                 name: "log-period-sheet--today--blush-dark", folder: folder)

        // Day 4, with the period's real first day two days ago: the start can move there instead.
        let (early, earlyArchive) = stores(back: 3)
        try snap(sheetOverToday(events: early, archive: earlyArchive, start: day(-2)), style: .light,
                 name: "log-period-sheet--past-move--blush-light", folder: folder)

        // The Cycles tab: current cycle, Log period, the Past cycles inline and the phases guide.
        func cyclesTab(events: EventStore, archive: ArchivedDataStore) -> some View {
            TabView(selection: .constant(3)) {
                Color.clear.tabItem { Label("Today", systemImage: "moonphase.first.quarter") }.tag(0)
                Color.clear.tabItem { Label("Calendar", systemImage: "calendar") }.tag(1)
                Color.clear.tabItem { Label("Tags", systemImage: "tag.fill") }.tag(2)
                SettingsCycleInfoView()
                    .tabItem { Label("Cycles", systemImage: "moon.circle") }.tag(3)
                Color.clear.tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
            }
            .tint(DS.Color.accent)
            .environment(\.auraPhase, PhaseWidgetSnapshot.make(events: events.events, archived: archive.archivedBlocks, today: now).phase)
            .environmentObject(events)
            .environmentObject(archive)
            .environmentObject(settings)
            .environmentObject(FertileStore())
            .environmentObject(PurchaseStore(listensForUpdates: false))
            .environmentObject(HealthSync())
        }
        try snap(cyclesTab(events: late, archive: lateArchive), style: .light, name: "cycles-tab--blush-light", folder: folder)
        settings.themeID = AppTheme.eclipse.id
        try snap(cyclesTab(events: late, archive: lateArchive), style: .dark, name: "cycles-tab--eclipse-dark", folder: folder)
        settings.themeID = AppTheme.blush.id

        // A fresh install: no cycle yet, nothing to archive.
        let empty = EventStore(preview: true)
        empty.events = []
        try snap(cyclesTab(events: empty, archive: ArchivedDataStore()), style: .light, name: "cycles-tab--empty--blush-light", folder: folder)
    }
}
