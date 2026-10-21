import SwiftUI
import XCTest
@testable import RhythmX

/// Phase colors are fixed since 2.0. Custom colors stored by 1.9.x under `phaseColor1`...`phaseColor4` are
/// never read, backups write the defaults, and a restore ignores whatever an older file carries.
@MainActor
final class FixedPhaseColorTests: XCTestCase {
    private let keys = ["phaseColor1", "phaseColor2", "phaseColor3", "phaseColor4"]
    /// Everything `AppSettings.apply` may write, saved and put back around each test.
    private let groupKeys = ["phaseColor1", "phaseColor2", "phaseColor3", "phaseColor4", "trackingMode", "defaultModeOnLaunch",
                             "dailyInsightsOn", "dailyInsightsHour", "dailyInsightsMinute", "dailyInsightsDiscreet"]
    private let standardKeys = ["notificationsEnabled", "notifyDayBefore", "notifyDayOf", "fertileStartOn",
                                "fertileOvulationOn", "weeklyCheckIn"]
    private var savedGroup: [String: Any] = [:]
    private var savedStandard: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        savedGroup = [:]
        savedStandard = [:]
        for key in groupKeys { savedGroup[key] = AppGroup.defaults.object(forKey: key) }
        for key in standardKeys { savedStandard[key] = UserDefaults.standard.object(forKey: key) }
    }

    override func tearDown() {
        for (store, keys, saved) in [(AppGroup.defaults, groupKeys, savedGroup), (UserDefaults.standard, standardKeys, savedStandard)] {
            for key in keys {
                if let value = saved[key] { store.set(value, forKey: key) } else { store.removeObject(forKey: key) }
            }
        }
        super.tearDown()
    }

    private func components(_ color: Color, dark: Bool) -> [Int] {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b].map { Int(($0 * 255).rounded()) }
    }

    private func both(_ color: Color) -> [[Int]] { [components(color, dark: false), components(color, dark: true)] }

    private let expected: [Event.EventType: [[Int]]] = [
        .menstrual:  [[201, 124, 124], [166, 96, 96]],
        .follicular: [[124, 166, 140], [95, 138, 112]],
        .ovulation:  [[201, 168, 124], [166, 136, 96]],
        .luteal:     [[140, 124, 166], [112, 95, 138]]
    ]

    func testCustomStoredColorsAreIgnoredEverywhere() {
        for key in keys { AppGroup.defaults.set("#112233", forKey: key) }
        let settings = AppSettings()
        let ds = [DS.Color.phase1, DS.Color.phase2, DS.Color.phase3, DS.Color.phase4]
        for (index, phase) in Event.EventType.allCases.enumerated() {
            let want = expected[phase]
            XCTAssertEqual(both(settings.phaseColor(for: phase)), want, "AppSettings \(phase)")
            XCTAssertEqual(both(phase.phaseColor), want, "Event.EventType.phaseColor \(phase)")
            XCTAssertEqual(both(phase.defaultPhaseColor), want, "default \(phase)")
            XCTAssertEqual(both(ds[index]), want, "DS.Color.phase\(index + 1)")
        }
    }

    func testFixedHexesMatchTheDefaults() {
        XCTAssertEqual(AppSettings.phaseColorHexes, ["#C97C7C", "#7CA68C", "#C9A87C", "#8C7CA6"])
    }

    func testBackupWritesTheFixedColors() {
        for key in keys { AppGroup.defaults.set("#ABCDEF", forKey: key) }
        XCTAssertEqual(AppSettings().settingsSnapshot().phaseColors, AppSettings.phaseColorHexes)
    }

    /// A 1.9.x-era file with custom phase colors still opens, and a Replace leaves the stored keys and the
    /// colors on screen as they were.
    func testOldBackupWithCustomPhaseColorsOpensAndRestoreIgnoresThem() throws {
        let settingsJSON: [String: Any] = [
            "phaseColors": ["#FF0000", "#00FF00", "#0000FF", "#FFFF00"],
            "notificationsEnabled": false,
            "notifyDayBefore": true,
            "notifyDayOf": true,
            "fertileStartOn": false,
            "fertileOvulationOn": false,
            "trackingMode": "cycle",
            "defaultModeOnLaunch": "last",
            "themeID": "default"
        ]
        let payloadJSON: [String: Any] = ["events": [], "archivedBlocks": [], "settings": settingsJSON]
        let body = try JSONSerialization.data(withJSONObject: payloadJSON)
        let envelope: [String: Any] = [
            "formatVersion": 1, "appVersion": "1.9.1", "createdAt": "2026-10-01T10:00:00Z",
            "encrypted": false, "body": body.base64EncodedString()
        ]
        let payload = try BackupFile.open(try JSONSerialization.data(withJSONObject: envelope), passphrase: nil)
        XCTAssertEqual(payload.settings.phaseColors, ["#FF0000", "#00FF00", "#0000FF", "#FFFF00"], "the field still decodes")

        AppGroup.defaults.set("#123123", forKey: "phaseColor1")
        AppGroup.defaults.removeObject(forKey: "phaseColor2")
        let settings = AppSettings()
        settings.apply(payload.settings)

        XCTAssertEqual(AppGroup.defaults.string(forKey: "phaseColor1"), "#123123", "restore does not write phase colors")
        XCTAssertNil(AppGroup.defaults.string(forKey: "phaseColor2"))
        XCTAssertEqual(both(settings.phaseColor(for: .follicular)), expected[.follicular])
        XCTAssertEqual(settings.settingsSnapshot().phaseColors, AppSettings.phaseColorHexes)
    }
}
