//  InsightsChartCategoryTests.swift
//  Swift Charts traps when a value falls outside an explicit color-scale domain, so every tag category the app
//  can store must be in `InsightsViewModel.categoryNames`. A saved Skin tag once crashed the app at launch.

import SwiftUI
import XCTest
@testable import RhythmX

@MainActor
final class InsightsChartCategoryTests: XCTestCase {

    private func events(tags: String) -> [Event] {
        var list = CycleGenerator.events(startDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())!, cycleLength: 28)
        for i in list.indices { list[i].tags = tags }
        return list
    }

    func testEveryStoredCategoryIsInTheChartDomain() {
        for category in TagCategory.allCases {
            XCTAssertTrue(InsightsViewModel.categoryNames.contains(category.rawValue), "\(category.rawValue) missing from the chart domain")
        }
    }

    func testStackedDataNeverEmitsAnUnlistedCategory() {
        let vm = InsightsViewModel(events: events(tags: "Skin:Face/Clear, Intimacy:Sex, Mystery:Thing, Plain"),
                                   archivedBlocks: [], appSettings: AppSettings())
        let names = Set(vm.stackedTagData.map(\.categoryName))
        XCTAssertTrue(names.isSubset(of: Set(InsightsViewModel.categoryNames)), "\(names)")
        XCTAssertTrue(names.contains("Skin"))
    }

    /// Lays out the real Insights screen with Skin, Intimacy and unknown-category tags saved; the old domain trapped here.
    func testInsightsScreenLaysOutWithSkinTagsSaved() throws {
        let store = EventStore(preview: true)
        store.events = events(tags: "Skin:Face/Clear, Intimacy:Sex, Mystery:Thing")
        let settings = AppSettings()
        settings.trackingMode = .cycle
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow ?? ($0 as? UIWindowScene)?.windows.first }.first)
        let previous = window.rootViewController
        defer { window.rootViewController = previous }
        let host = UIHostingController(rootView: ScrollView { InsightsView() }
            .environmentObject(store).environmentObject(ArchivedDataStore()).environmentObject(settings))
        window.rootViewController = host
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        XCTAssertNotNil(host.view)
    }
}
