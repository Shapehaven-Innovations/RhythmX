//  SkinRampTests.swift
//
//  The skin severity ramp: hue guard, text contrast, monotonic fills, buckets, and no phase colour as a fill.

import XCTest
@testable import RhythmX

final class SkinRampTests: XCTestCase {
    private let phases: [Event.EventType] = [.menstrual, .follicular, .ovulation, .luteal]

    private func name(_ theme: AppTheme, _ isDark: Bool) -> String { "\(theme.name) \(isDark ? "dark" : "light")" }

    func testNeutralTargetPerTheme() {
        let expected: [(AppTheme, Bool, Bool)] = [
            (.blush, false, false), (.blush, true, true),
            (.blueMoon, false, false), (.blueMoon, true, false),
            (.harvestMoon, false, true), (.harvestMoon, true, true),
            (.eclipse, false, true), (.eclipse, true, true),
        ]
        for (theme, isDark, neutral) in expected {
            let ramp = SkinRamp.make(theme: theme, isDark: isDark)
            XCTAssertEqual(ramp.usesNeutralTarget, neutral, name(theme, isDark))
            let p = isDark ? theme.dark : theme.light
            XCTAssertEqual(ramp.fills.last, neutral ? p.ink : p.accent, "\(name(theme, isDark)): top step is the target")
        }
    }

    func testTextContrastAtLeast4_5EverywhereForAllThemesAndAppearances() {
        for theme in AppTheme.all {
            for isDark in [false, true] {
                let ramp = SkinRamp.make(theme: theme, isDark: isDark)
                let p = isDark ? theme.dark : theme.light
                XCTAssertEqual(ramp.fills.count, 5)
                XCTAssertEqual(ramp.text.count, 5)
                for i in 0..<5 {
                    XCTAssertTrue(ramp.text[i] == p.ink || ramp.text[i] == p.card, "\(name(theme, isDark)) step \(i + 1)")
                    XCTAssertGreaterThanOrEqual(SkinRamp.contrast(ramp.fills[i], ramp.text[i]), SkinRamp.minimumTextContrast,
                                                "\(name(theme, isDark)) step \(i + 1)")
                }
                XCTAssertEqual(ramp.empty, RGB.mix(p.card, p.ink, 0.06))
                XCTAssertEqual(ramp.emptyText, p.muted)
            }
        }
    }

    func testFillsStrictlyMonotonicTowardTarget() {
        for theme in AppTheme.all {
            for isDark in [false, true] {
                let ramp = SkinRamp.make(theme: theme, isDark: isDark)
                let card = (isDark ? theme.dark : theme.light).card
                let contrasts = ramp.fills.map { SkinRamp.contrast($0, card) }
                for i in 1..<contrasts.count {
                    XCTAssertGreaterThan(contrasts[i], contrasts[i - 1], "\(name(theme, isDark)) step \(i + 1)")
                }
            }
        }
    }

    func testBuckets() {
        let cases: [(Int?, Int)] = [(nil, 0), (0, 0), (1, 1), (10, 1), (11, 2), (20, 2), (21, 3), (35, 3),
                                    (36, 4), (50, 4), (51, 5), (100, 5)]
        for (percent, bucket) in cases {
            XCTAssertEqual(SkinRamp.bucket(percent: percent), bucket, "\(String(describing: percent))")
        }
        let ramp = SkinRamp.make(theme: .blush, isDark: false)
        XCTAssertEqual(ramp.fill(percent: nil), ramp.empty)
        XCTAssertEqual(ramp.textColour(percent: 0), ramp.emptyText)
        XCTAssertEqual(ramp.fill(percent: 60), ramp.fills[4])
        XCTAssertEqual(ramp.textColour(percent: 15), ramp.text[1])
    }

    func testPhaseColoursAreNeverAFill() {
        for theme in AppTheme.all {
            for isDark in [false, true] {
                let ramp = SkinRamp.make(theme: theme, isDark: isDark)
                for phase in phases {
                    let phaseColour = AuraPalette.phaseRGB(phase, isDark: isDark)
                    XCTAssertFalse(ramp.fills.contains(phaseColour), "\(name(theme, isDark)) \(phase)")
                    XCTAssertNotEqual(ramp.empty, phaseColour, "\(name(theme, isDark)) \(phase)")
                }
            }
        }
    }

    func testHueDistance() {
        let red = RGB(r: 255, g: 0, b: 0), cyan = RGB(r: 0, g: 255, b: 255), blue = RGB(r: 0, g: 0, b: 255)
        XCTAssertEqual(SkinRamp.hueDistance(red, cyan), 180, accuracy: 0.001)
        XCTAssertEqual(SkinRamp.hueDistance(red, red), 0, accuracy: 0.001)
        XCTAssertEqual(SkinRamp.hueDistance(red, blue), SkinRamp.hueDistance(blue, red), accuracy: 0.001)
        XCTAssertEqual(SkinRamp.hueDistance(red, blue), 120, accuracy: 0.001)
        XCTAssertEqual(SkinRamp.hueDegrees(RGB(r: 128, g: 128, b: 128)), 0)
    }

    func testContrastFormula() {
        XCTAssertEqual(SkinRamp.contrast(RGB(r: 0, g: 0, b: 0), RGB(r: 255, g: 255, b: 255)), 21, accuracy: 0.001)
        XCTAssertEqual(SkinRamp.contrast(RGB(r: 10, g: 20, b: 30), RGB(r: 10, g: 20, b: 30)), 1, accuracy: 0.001)
    }
}
