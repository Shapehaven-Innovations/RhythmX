import XCTest
@testable import RhythmX

/// Step 4a: the living page background's colours and stars are pure and deterministic.
final class AuraPaletteTests: XCTestCase {

    func testSameInputsGiveTheSamePalette() {
        for theme in AppTheme.all {
            for dark in [false, true] {
                XCTAssertEqual(AuraPalette.make(phase: .luteal, theme: theme, isDark: dark, hour: 20),
                               AuraPalette.make(phase: .luteal, theme: theme, isDark: dark, hour: 20))
            }
        }
    }

    func testPhaseChangesTheHue() {
        for theme in AppTheme.all {
            for dark in [false, true] {
                let colours = Event.EventType.allCases.map {
                    AuraPalette.make(phase: $0, theme: theme, isDark: dark, hour: 14).mesh[0]
                }
                XCTAssertEqual(Set(colours.map { "\($0.r),\($0.g),\($0.b)" }).count, 4, "\(theme.id) dark=\(dark)")
                XCTAssertEqual(AuraPalette.make(phase: .menstrual, theme: theme, isDark: dark, hour: 14).glow,
                               AuraPalette.phaseRGB(.menstrual, isDark: dark))
            }
        }
    }

    func testEveningIsWarmerThanAfternoon() {
        for theme in AppTheme.all {
            for dark in [false, true] {
                for phase in Event.EventType.allCases {
                    let evening = AuraPalette.make(phase: phase, theme: theme, isDark: dark, hour: 19)
                    let afternoon = AuraPalette.make(phase: phase, theme: theme, isDark: dark, hour: 14)
                    XCTAssertGreaterThan(evening.warmth, afternoon.warmth, "\(theme.id) dark=\(dark) \(phase)")
                }
            }
        }
    }

    func testTimeOfDayBands() {
        XCTAssertEqual(AuraPalette.TimeOfDay(hour: 5), .morning)
        XCTAssertEqual(AuraPalette.TimeOfDay(hour: 12), .afternoon)
        XCTAssertEqual(AuraPalette.TimeOfDay(hour: 17), .evening)
        XCTAssertEqual(AuraPalette.TimeOfDay(hour: 22), .night)
        XCTAssertEqual(AuraPalette.TimeOfDay(hour: 3), .night)
    }

    func testPhaseColoursAreTheFixedAppColours() {
        let hexes = AppSettings.phaseColorHexes.map { hex -> RGB in
            let v = Int(hex.dropFirst(), radix: 16)!
            return RGB(r: (v >> 16) & 0xFF, g: (v >> 8) & 0xFF, b: v & 0xFF)
        }
        XCTAssertEqual(Event.EventType.allCases.map { AuraPalette.phaseRGB($0, isDark: false) }, hexes)
    }

    func testStarsOnlyAtNightAndDensestInEclipse() {
        for theme in AppTheme.all {
            XCTAssertFalse(AuraPalette.stars(theme: theme, isDark: false).isVisible, "no stars on light pages")
            XCTAssertTrue(AuraPalette.stars(theme: theme, isDark: true).isVisible)
        }
        let eclipse = AuraPalette.stars(theme: .eclipse, isDark: true)
        for theme in AppTheme.all where theme != .eclipse {
            let other = AuraPalette.stars(theme: theme, isDark: true)
            XCTAssertGreaterThan(eclipse.count + eclipse.brightCount, other.count + other.brightCount)
            XCTAssertGreaterThan(eclipse.opacity, other.opacity)
        }
    }

    func testStarFieldIsDeterministicAndInsideThePage() {
        let density = AuraPalette.stars(theme: .eclipse, isDark: true)
        let a = AuraStarField.stars(seed: 5, stars: density)
        XCTAssertEqual(a, AuraStarField.stars(seed: 5, stars: density))
        XCTAssertNotEqual(a, AuraStarField.stars(seed: 6, stars: density))
        XCTAssertEqual(a.count, density.count + density.brightCount + density.glints)
        XCTAssertTrue(a.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        XCTAssertTrue(a.contains { $0.twinkles } && a.contains { !$0.twinkles }, "a few twinkle, most do not")
        XCTAssertEqual(a.filter { $0.kind == .glint }.count, density.glints)
    }
}
