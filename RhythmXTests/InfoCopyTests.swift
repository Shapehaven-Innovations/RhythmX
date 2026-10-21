import XCTest
@testable import RhythmX

/// The explanations behind the info circles: one place, plain copy, and the lines that must stay visible never
/// move behind a circle.
final class InfoCopyTests: XCTestCase {

    private func assertPlain(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(text.contains("\u{2014}"), "em dash in: \(text)", file: file, line: line)
        XCTAssertFalse(text.contains("\u{2013}"), "en dash in: \(text)", file: file, line: line)
        XCTAssertFalse(text.lowercased().contains("goddess"), file: file, line: line)
        XCTAssertFalse(text.unicodeScalars.contains { $0.properties.isEmojiPresentation }, "emoji in: \(text)",
                       file: file, line: line)
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, file: file, line: line)
    }

    func testEveryTopicIsPlainCopy() {
        XCTAssertFalse(InfoCopy.all.isEmpty)
        for topic in InfoCopy.all {
            assertPlain(topic.title)
            XCTAssertFalse(topic.paragraphs.isEmpty, topic.id)
            topic.paragraphs.forEach { assertPlain($0) }
            topic.footnote.map { assertPlain($0) }
        }
    }

    func testTopicIdsAreUnique() {
        let ids = InfoCopy.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTheAppWideTopicsExist() {
        let ids = Set(InfoCopy.all.map(\.id))
        for id in ["notifications.period", "notifications.fertile", "notifications.dailyInsights",
                   "notifications.discreet", "notifications.weekly", "settings.health", "settings.calendar",
                   "settings.backup", "settings.plus", "settings.greeting", "cycles.newCycle",
                   "cycles.freshStretch", "share", "export.privacy"] {
            XCTAssertTrue(ids.contains(id), "missing \(id)")
        }
    }

    func testVoiceOverLabelNamesTheTopic() {
        XCTAssertEqual(InfoCopy.dailyInsights.accessibilityLabel, "About Daily insights")
        XCTAssertEqual(InfoCopy.appleHealth.accessibilityLabel, "About Apple Health")
    }

    /// The disclaimers and safety lines are shown on the page, never only behind a circle.
    func testRequiredVisibleLinesAreNotHiddenInInfo() {
        let hidden = InfoCopy.all.flatMap(\.paragraphs).joined(separator: " ")
        XCTAssertFalse(hidden.contains(PlanningInsightsView.disclaimer))
        XCTAssertEqual(InfoCopy.alwaysVisible, [PlanningInsightsView.disclaimer, MenopauseInsightsView.disclaimer])
    }

    func testDailyInsightsExplainsBackgroundRefreshAndFallback() {
        let text = InfoCopy.dailyInsights.paragraphs.joined(separator: " ")
        XCTAssertTrue(text.contains("Background App Refresh"))
        XCTAssertTrue(text.contains("standard note"))
        XCTAssertEqual(InfoCopy.dailyInsights.footnote, MenopauseInsightsView.disclaimer)
    }

    func testDiscreetExplainsTheLockScreenText() {
        XCTAssertTrue(InfoCopy.discreetLockScreen.paragraphs.joined().contains(NotificationScheduler.discreetInsightBody))
    }

    func testInfoPlistStringsAreAccurate() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertNil(info["NSUserNotificationsUsageDescription"], "iOS does not read it")
        let health = try XCTUnwrap(info["NSHealthShareUsageDescription"] as? String)
        XCTAssertTrue(health.contains("on Today"), health)
        XCTAssertFalse(health.contains("in Insights"), health)
        for key in ["NSCalendarsFullAccessUsageDescription", "NSCalendarsWriteOnlyAccessUsageDescription"] {
            let text = try XCTUnwrap(info[key] as? String)
            XCTAssertFalse(text.contains("Nothing leaves this device"), key)
            XCTAssertTrue(text.contains("iCloud"), key)
        }
        XCTAssertFalse(InfoCopy.appleHealth.paragraphs.joined(separator: " ").contains("in Insights"))
        XCTAssertTrue(InfoCopy.appleHealth.paragraphs.joined(separator: " ").contains("on Today"))
    }

    func testShareTopicSaysNothingIsUploaded() {
        let text = InfoCopy.share.paragraphs.joined(separator: " ")
        XCTAssertTrue(text.contains("Nothing is uploaded"))
        XCTAssertTrue(text.contains("Tags, notes and dates are never included"))
    }

    func testExportPrivacyKeepsTheShippedNote() {
        XCTAssertEqual(InfoCopy.exportPrivacy.paragraphs.first, ExportCopy.privacyNote)
    }
}
