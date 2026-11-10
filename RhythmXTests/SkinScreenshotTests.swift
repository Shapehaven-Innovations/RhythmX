//  SkinScreenshotTests.swift
//  Writes Skin screenshots (Today card, face and full body, phase grid, the two log styles) for every theme in
//  light and dark, plus accessibility-size captures, for a human to compare with the design.
//  Runs only when the test runner has `RHYTHMX_SCREENSHOT_DIR` (pass `TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR=<dir>`).
//  Nothing is written to the stores: the event store is a preview store, the archive is set in memory only.

import Foundation
import SwiftUI
import XCTest
@testable import RhythmX

@MainActor
final class SkinScreenshotTests: XCTestCase {

    private func window() throws -> UIWindow {
        try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow ?? ($0 as? UIWindowScene)?.windows.first }.first)
    }

    private func allViews(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(allViews) }

    private func snap<V: View>(_ view: V, style: UIUserInterfaceStyle, name: String, folder: URL,
                               wait: Double = 1.4, fullBody: Bool = false) throws {
        let window = try window()
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = style
        let previousStyle = window.overrideUserInterfaceStyle
        window.overrideUserInterfaceStyle = style
        defer { window.overrideUserInterfaceStyle = previousStyle }
        let previous = window.rootViewController
        window.rootViewController = host
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        if fullBody {
            // The Face / Full body picker keeps its state private, so drive the real control.
            let segments = allViews(host.view).compactMap { $0 as? UISegmentedControl }
            if let control = segments.first(where: { $0.numberOfSegments == 2 && $0.titleForSegment(at: 1) == "Full body" }) {
                control.selectedSegmentIndex = 1
                control.sendActions(for: .valueChanged)
                RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            }
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(name).png"))
        host.dismiss(animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        window.rootViewController = previous
    }

    func testWritesSkinScreenshotsForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["RHYTHMX_SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_RHYTHMX_SCREENSHOT_DIR to write review screenshots")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let settings = AppSettings()
        let savedLogStyle = UserDefaults.standard.object(forKey: "skinLogStyle")
        let saved = (settings.trackingMode, settings.themeID,
                     AppGroup.defaults.object(forKey: PersistenceKeys.plusExpiry) as? Date)
        defer {
            settings.trackingMode = saved.0
            settings.themeID = saved.1
            AppGroup.defaults.set(saved.2, forKey: PersistenceKeys.plusExpiry)
            if let savedLogStyle { UserDefaults.standard.set(savedLogStyle, forKey: "skinLogStyle") }
            else { UserDefaults.standard.removeObject(forKey: "skinLogStyle") }
        }
        // Plus themes are drawn only while Plus is active.
        AppGroup.defaults.set(Date().addingTimeInterval(86_400 * 30), forKey: PersistenceKeys.plusExpiry)
        settings.trackingMode = .cycle

        let calendar = Calendar.current
        var noon = calendar.dateComponents([.year, .month, .day], from: Date())
        noon.hour = 19
        let now = calendar.date(from: noon)!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))! }

        // Fixture: three archived 28-day cycles plus the current one (day 15), skin on about 40% of days,
        // biased to luteal and menstrual days.
        let areas: [SkinTag.Area] = [.chin, .jaw, .back, .forehead, .cheeks, .chest, .nose, .neck]
        let kindSets: [Set<SkinTag.Kind>] = [[.acne], [.breakout], [.acne, .irritated], [.dry, .flaky], [.oily],
                                              [.breakout, .irritated], [.clear]]
        let colours: [SkinTag.Colour?] = [.red, .pink, nil, .darkSpots, .red, .pale, nil]
        func cycle(start: Int, seed: Int, lengthDays: Int = 28) -> [Event] {
            var events = CycleGenerator.events(startDate: day(start), cycleLength: 28)
            for i in events.indices {
                let phase = events[i].eventType
                let chance: Int
                switch phase {
                case .luteal: chance = 68
                case .menstrual: chance = 55
                case .ovulation: chance = 25
                default: chance = 18
                }
                let roll = (i * 37 + seed * 53 + 11) % 100
                guard roll < chance else { continue }
                var tags: [String] = []
                let k = (i + seed) % kindSets.count
                if let tag = SkinTag(area: areas[(i * 3 + seed) % areas.count], kinds: kindSets[k], colour: colours[k]) {
                    tags.append(tag.raw)
                }
                if roll % 3 == 0, let second = SkinTag(area: areas[(i + seed * 2 + 1) % areas.count],
                                                       kinds: kindSets[(k + 2) % kindSets.count], colour: colours[(k + 2) % colours.count]) {
                    tags.append(second.raw)
                }
                if roll % 11 == 0 { tags.append("Other:Acne") }
                if i % 9 == 4 { tags.append("Intimacy:Sex") }
                if i % 18 == 4 { tags.append("Planning:Intercourse") }
                events[i].tags = tags.joined(separator: ", ")
            }
            return events
        }
        let events = EventStore(preview: true)
        events.events = cycle(start: -14, seed: 0).filter { $0.date <= now }
        let archive = ArchivedDataStore()
        archive.archivedBlocks = (1...3).map { n in
            let past = cycle(start: -14 - 28 * n, seed: n)
            return ArchivedDataBlock(date: day(-14 - 28 * n),
                                     groupedEvents: Dictionary(grouping: past, by: \.eventType)
                                        .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) })
        }
        let health = HealthSync()
        let snapshot = PhaseWidgetSnapshot.make(events: events.events, archived: archive.archivedBlocks, today: now)

        func env<V: View>(_ view: V, phase: Event.EventType? = .luteal) -> some View {
            view
                .environment(\.auraPhase, phase)
                .environmentObject(events).environmentObject(archive).environmentObject(settings)
                .environmentObject(FertileStore()).environmentObject(health)
        }

        let pairs: [(String, String, UIUserInterfaceStyle)] = AppTheme.all.flatMap { theme in
            [(theme.name.lowercased().replacingOccurrences(of: " ", with: "-"), theme.id, UIUserInterfaceStyle.light), (theme.name.lowercased().replacingOccurrences(of: " ", with: "-"), theme.id, .dark)]
        }
        for (slug, themeID, style) in pairs {
            let suffix = "\(slug)-\(style == .dark ? "dark" : "light")"
            settings.themeID = themeID

            let stats = SkinStats(events: events.events, archivedBlocks: archive.archivedBlocks, today: now, window: .all)
            let card = ScrollView {
                SkinTodayCard(stats: stats, todayPhase: snapshot.phase, cycleDay: snapshot.cycleDay, mode: .cycle,
                              todaySkin: [], onLog: {}, onDetails: {})
                    .padding(DS.Spacing.md)
            }.themedPage()
            try snap(env(card, phase: snapshot.phase), style: style, name: "skin-today-\(suffix)", folder: folder)

            let screen = NavigationStack { SkinInsightsView(now: now) }
            try snap(env(screen), style: style, name: "skin-body-\(suffix)", folder: folder)
            try snap(env(screen), style: style, name: "skin-fullbody-\(suffix)", folder: folder, fullBody: true)

            let grid = ScrollView {
                SkinPhaseGridView(events: events.events, archivedBlocks: archive.archivedBlocks, today: now, window: .all)
                    .padding(DS.Spacing.md)
            }.themedPage()
            try snap(env(grid), style: style, name: "skin-grid-\(suffix)", folder: folder)

            for logStyle in ["chips", "map"] {
                UserDefaults.standard.set(logStyle, forKey: "skinLogStyle")
                let form = Color.clear.themedPage().sheet(isPresented: .constant(true)) {
                    env(TagFormView(initialDate: now, initialCategory: .skin))
                }
                try snap(env(form), style: style, name: "skin-log-\(logStyle)-\(suffix)", folder: folder, wait: 1.8)
            }
        }

        // Accessibility size, Blush light.
        settings.themeID = AppTheme.blush.id
        let large = ScrollView {
            SkinPhaseGridView(events: events.events, archivedBlocks: archive.archivedBlocks, today: now, window: .all)
                .padding(DS.Spacing.md)
        }.themedPage().environment(\.dynamicTypeSize, .accessibility3)
        try snap(env(large), style: .light, name: "skin-grid-ax3", folder: folder)
        UserDefaults.standard.set("map", forKey: "skinLogStyle")
        let largeForm = Color.clear.themedPage().sheet(isPresented: .constant(true)) {
            env(TagFormView(initialDate: now, initialCategory: .skin)).environment(\.dynamicTypeSize, .accessibility3)
        }
        try snap(env(largeForm), style: .light, name: "skin-log-ax3", folder: folder, wait: 1.8)

        // The default category of the Add Tags sheet must be Symptom in every mode (Task 13).
        for mode in TrackingMode.allCases {
            settings.trackingMode = mode
            let form = Color.clear.themedPage().sheet(isPresented: .constant(true)) {
                env(TagFormView(), phase: mode == .menopause ? nil : .luteal)
            }
            try snap(env(form, phase: mode == .menopause ? nil : .luteal), style: .light,
                     name: "tagform-default-\(mode.rawValue)", folder: folder, wait: 1.8)
        }
    }
}
