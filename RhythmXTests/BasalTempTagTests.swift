import XCTest
@testable import RhythmX

@MainActor
final class BasalTempTagTests: XCTestCase {
    func testCategoryExistsWithStableRawValue() {
        XCTAssertEqual(TagCategory.basalTemp.rawValue, "Basal Temp")
        XCTAssertTrue(TagCategory.allCases.contains(.basalTemp))
    }

    func testLibraryHasElevatedBBT() {
        XCTAssertEqual(TagLibrary.tags[.basalTemp], ["Elevated BBT"])
    }

    func testEveryCategoryHasLibraryTagsAndAColor() {
        for cat in TagCategory.allCases {
            XCTAssertFalse((TagLibrary.tags[cat] ?? []).isEmpty, "\(cat.rawValue) has no library tags")
            XCTAssertNotNil(InsightsViewModel.categoryColors[cat.rawValue], "\(cat.rawValue) has no insights color")
        }
    }

    func testLegendIncludesBasalTemp() {
        let vm = InsightsViewModel(events: [], archivedBlocks: [], appSettings: AppSettings())
        XCTAssertTrue(vm.categoryLegendItems.map(\.name).contains("Basal Temp"))
    }

    func testCategoryTotalsCountBasalTemp() {
        let e = Event(eventType: .luteal, date: Date(), note: "n", tags: "Basal Temp:Elevated BBT, Mood:Calm")
        let vm = InsightsViewModel(events: [e], archivedBlocks: [], appSettings: AppSettings())
        let total = vm.tagCategoryTotals.first { $0.category == "Basal Temp" }
        XCTAssertEqual(total?.count, 1)
    }
}
