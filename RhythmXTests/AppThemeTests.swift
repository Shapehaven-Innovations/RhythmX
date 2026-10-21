import XCTest
import SwiftUI
import Combine
@testable import RhythmX

/// Task 16: moon themes. Pure palette rules, the Plus fallback, and WCAG AA contrast for every theme.
final class AppThemeTests: XCTestCase {
    private let suiteName = "test.apptheme"
    /// The suite the theme rules are checked against (`DS.Theme.resolve(defaults:)`), never the shared store.
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// `DS.Color` reads the real shared store, so the two tests that go through it snapshot the keys they touch
    /// and put them back when the test ends, whichever way it ends.
    private func useSharedThemeStore() {
        let themeID = AppGroup.defaults.string(forKey: DS.Theme.storageKey)
        let plusExpiry = AppGroup.defaults.object(forKey: PersistenceKeys.plusExpiry) as? Date
        addTeardownBlock {
            AppGroup.defaults.set(themeID, forKey: DS.Theme.storageKey)
            AppGroup.defaults.set(plusExpiry, forKey: PersistenceKeys.plusExpiry)
        }
    }

    private func rgb(_ hex: String) -> RGB {
        let v = Int(hex.dropFirst(), radix: 16)!
        return RGB(r: (v >> 16) & 0xFF, g: (v >> 8) & 0xFF, b: v & 0xFF)
    }

    /// WCAG 2.x relative luminance and contrast ratio (pure, test-only).
    private func luminance(_ c: RGB) -> Double {
        func channel(_ v: Int) -> Double {
            let s = Double(v) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    private func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func components(_ color: Color, dark: Bool) -> [Int] {
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())]
    }

    // MARK: - Catalogue

    func testCatalogueOrderAndPlusFlags() {
        XCTAssertEqual(AppTheme.all.map(\.id), ["blush", "blueMoon", "harvestMoon", "eclipse"])
        XCTAssertEqual(AppTheme.all.map(\.name), ["Blush", "Blue Moon", "Harvest Moon", "Eclipse"])
        XCTAssertEqual(AppTheme.all.map(\.isPlus), [false, true, true, true])
        XCTAssertEqual(AppTheme.blush.id, "blush")
        XCTAssertEqual(AppTheme.defaultID, "blush")
        XCTAssertEqual(DS.Theme.storageKey, "themeID")
    }

    // MARK: - Blush is unchanged

    func testBlushMatchesCurrentDesignSystemValues() {
        // The literals DesignSystem.swift held before themes existed.
        let light = AppTheme.blush.light
        XCTAssertEqual(light.page, RGB(r: 251, g: 241, b: 243))
        XCTAssertEqual(light.card, RGB(r: 255, g: 255, b: 255))
        XCTAssertEqual(light.accent, RGB(r: 94, g: 38, b: 79))
        XCTAssertEqual(light.onAccent, RGB(r: 255, g: 255, b: 255))
        XCTAssertEqual(light.moon, RGB(r: 240, g: 179, b: 196))
        XCTAssertEqual(light.waveBack, RGB(r: 196, g: 130, b: 170))
        XCTAssertEqual(light.waveMid, RGB(r: 176, g: 104, b: 154))
        XCTAssertEqual(light.waveFront, RGB(r: 139, g: 63, b: 107))

        let dark = AppTheme.blush.dark
        XCTAssertEqual(dark.page, RGB(r: 27, g: 15, b: 30))
        XCTAssertEqual(dark.card, RGB(r: 43, g: 24, b: 48))
        XCTAssertEqual(dark.accent, RGB(r: 232, g: 165, b: 184))
        XCTAssertEqual(dark.onAccent, RGB(r: 27, g: 15, b: 30))
        XCTAssertEqual(dark.moon, RGB(r: 244, g: 228, b: 236))
        XCTAssertEqual(dark.waveBack, RGB(r: 196, g: 138, b: 168))
        XCTAssertEqual(dark.waveMid, RGB(r: 154, g: 92, b: 134))
        XCTAssertEqual(dark.waveFront, RGB(r: 58, g: 27, b: 58))

        // The asset catalog AccentColor (0.369, 0.149, 0.310 / 0.910, 0.647, 0.722) is the same colour.
        XCTAssertEqual(light.accent, RGB(r: Int((0.369 * 255).rounded()), g: Int((0.149 * 255).rounded()), b: Int((0.310 * 255).rounded())))
        XCTAssertEqual(dark.accent, RGB(r: Int((0.910 * 255).rounded()), g: Int((0.647 * 255).rounded()), b: Int((0.722 * 255).rounded())))

        // And DS resolves to exactly those values while Blush is selected.
        useSharedThemeStore()
        AppGroup.defaults.set("blush", forKey: DS.Theme.storageKey)
        XCTAssertEqual(components(DS.Color.pageBackground, dark: false), [251, 241, 243])
        XCTAssertEqual(components(DS.Color.pageBackground, dark: true), [27, 15, 30])
        XCTAssertEqual(components(DS.Color.cardBackground, dark: false), [255, 255, 255])
        XCTAssertEqual(components(DS.Color.cardBackground, dark: true), [43, 24, 48])
        XCTAssertEqual(components(DS.Color.accent, dark: false), [94, 38, 79])
        XCTAssertEqual(components(DS.Color.accent, dark: true), [232, 165, 184])
        XCTAssertEqual(components(DS.Color.waveFront, dark: false), [139, 63, 107])
        XCTAssertEqual(components(DS.Color.moon, dark: true), [244, 228, 236])
        // Blush keeps the system text colours it always had.
        XCTAssertEqual(components(DS.Color.primaryText, dark: false), components(Color(UIColor.label), dark: false))
        XCTAssertEqual(components(DS.Color.secondaryText, dark: true), components(Color(UIColor.secondaryLabel), dark: true))
    }

    func testPlusPalettesMatchTheSpec() {
        let b = AppTheme.blueMoon
        XCTAssertEqual([b.light.page, b.light.card, b.light.ink, b.light.muted, b.light.accent, b.light.onAccent, b.light.moon],
                       ["#DCE5F7", "#F4F7FD", "#131B3D", "#4A5580", "#2A3C8F", "#FFFFFF", "#8FA6E8"].map(rgb))
        XCTAssertEqual([b.dark.page, b.dark.card, b.dark.ink, b.dark.muted, b.dark.accent, b.dark.onAccent, b.dark.moon],
                       ["#0A1030", "#151D4A", "#E8EDFF", "#A3B0DD", "#9FB4FF", "#0A1030", "#C7D3FF"].map(rgb))
        let h = AppTheme.harvestMoon
        XCTAssertEqual([h.light.page, h.light.card, h.light.ink, h.light.muted, h.light.accent, h.light.onAccent, h.light.moon],
                       ["#F6DDB4", "#FFF6E6", "#2B1706", "#6B4F34", "#7A3E0A", "#FFFFFF", "#E8A23A"].map(rgb))
        XCTAssertEqual([h.dark.page, h.dark.card, h.dark.ink, h.dark.muted, h.dark.accent, h.dark.onAccent, h.dark.moon],
                       ["#2A1A08", "#3D2711", "#FBEFD9", "#D2B78E", "#FFB84D", "#2A1A08", "#FFD28A"].map(rgb))
        let e = AppTheme.eclipse
        XCTAssertEqual([e.light.page, e.light.card, e.light.ink, e.light.muted, e.light.accent, e.light.onAccent, e.light.moon],
                       ["#E3E4E9", "#F7F7F9", "#14161C", "#555966", "#A9461A", "#FFFFFF", "#AEB3C2"].map(rgb))
        XCTAssertEqual([e.dark.page, e.dark.card, e.dark.ink, e.dark.muted, e.dark.accent, e.dark.onAccent, e.dark.moon],
                       ["#0C0D10", "#1B1D23", "#EEEFF3", "#A0A4B2", "#F0A36B", "#0C0D10", "#D5D8E0"].map(rgb))
    }

    // MARK: - Plus gate

    func testPlusThemesFallBackToBlushWithoutPlus() {
        for theme in AppTheme.all where theme.isPlus {
            XCTAssertEqual(AppTheme.effective(id: theme.id, canUsePlus: false), AppTheme.blush, theme.id)
            XCTAssertEqual(AppTheme.effective(id: theme.id, canUsePlus: true), theme, theme.id)
        }
        XCTAssertEqual(AppTheme.effective(id: "blush", canUsePlus: false), AppTheme.blush)
        XCTAssertEqual(AppTheme.effective(id: "blush", canUsePlus: true), AppTheme.blush)
        XCTAssertEqual(AppTheme.effective(id: "no such theme", canUsePlus: true), AppTheme.blush, "unknown ids fall back too")
    }

    func testStoredIdKeptWhenFallingBack() {
        // The same key AppSettings.themeID writes, in the test suite instead of the shared store.
        defaults.set("eclipse", forKey: DS.Theme.storageKey)
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

        // No Plus cached: Blush is shown, the choice is not touched.
        XCTAssertEqual(DS.Theme.resolve(defaults: defaults, now: now, grace: 0).id, "blush")
        XCTAssertEqual(defaults.string(forKey: DS.Theme.storageKey), "eclipse")

        // Plus comes back: the stored theme is restored without the user choosing it again.
        Entitlement(plusExpiry: now.addingTimeInterval(30 * 86_400), dayPassExpiry: nil).save(to: defaults)
        XCTAssertEqual(DS.Theme.resolve(defaults: defaults, now: now, grace: 0).id, "eclipse")

        // In the app a lapsed subscription has no grace; the widget extension keeps the 3-day grace.
        Entitlement(plusExpiry: now.addingTimeInterval(-86_400), dayPassExpiry: nil).save(to: defaults)
        XCTAssertEqual(DS.Theme.resolve(defaults: defaults, now: now, grace: 0).id, "blush")
        XCTAssertEqual(DS.Theme.resolve(defaults: defaults, now: now, grace: Entitlement.plusGrace).id, "eclipse")
        XCTAssertEqual(DS.Theme.resolve(defaults: defaults, now: now.addingTimeInterval(Entitlement.plusGrace),
                                        grace: Entitlement.plusGrace).id, "blush")
        XCTAssertEqual(defaults.string(forKey: DS.Theme.storageKey), "eclipse", "falling back never rewrites the choice")
    }

    func testResolveReadsThemeFromGivenDefaults() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        defaults.set("harvestMoon", forKey: DS.Theme.storageKey)
        XCTAssertEqual(DS.Theme.resolve(defaults: defaults, now: now, grace: 0).id, "blush")
        Entitlement(plusExpiry: now.addingTimeInterval(60), dayPassExpiry: nil).save(to: defaults)
        XCTAssertEqual(DS.Theme.resolve(defaults: defaults, now: now, grace: 0).id, "harvestMoon")
        XCTAssertEqual(DS.Theme.resolve(defaults: UserDefaults(suiteName: "test.apptheme.empty")!, now: now, grace: 0).id, "blush",
                       "no stored id means Blush")
    }

    // MARK: - Contrast

    func testTextAndAccentContrastMeetAA() {
        for theme in AppTheme.all {
            for (appearance, p) in [("light", theme.light), ("dark", theme.dark)] {
                let name = "\(theme.name) \(appearance)"
                XCTAssertGreaterThanOrEqual(contrast(p.ink, p.page), 4.5, "\(name): ink on page")
                XCTAssertGreaterThanOrEqual(contrast(p.muted, p.page), 4.5, "\(name): muted on page")
                XCTAssertGreaterThanOrEqual(contrast(p.accent, p.page), 4.5, "\(name): accent on page")
                XCTAssertGreaterThanOrEqual(contrast(p.onAccent, p.accent), 4.5, "\(name): onAccent on accent")
                XCTAssertGreaterThanOrEqual(contrast(p.ink, p.card), 4.5, "\(name): ink on card")
            }
        }
    }

    // MARK: - Living background (Phase Aura)

    /// Body text keeps AA on every colour of the aura, for every theme, appearance, phase and time of day.
    func testTextOnTheAuraMeetsAA() {
        for theme in AppTheme.all {
            for (dark, p) in [(false, theme.light), (true, theme.dark)] {
                for phase in Event.EventType.allCases.map(Optional.some) + [nil] {
                    for hour in [8, 14, 19, 23] {
                        let aura = AuraPalette.make(phase: phase, theme: theme, isDark: dark, hour: hour)
                        for (i, colour) in aura.mesh.enumerated() {
                            let name = "\(theme.name) dark=\(dark) \(phase.map(\.rawValue) ?? "none") \(hour)h cell \(i)"
                            XCTAssertGreaterThanOrEqual(contrast(p.ink, colour), 4.5, "\(name): ink on aura")
                            XCTAssertGreaterThanOrEqual(contrast(p.muted, colour), 4.5, "\(name): muted on aura")
                        }
                    }
                }
            }
        }
    }

    /// The moon disc's edge reads against the page (3:1, non-text contrast) and against the aura's centre,
    /// where the disc sits, in all four themes, light and dark.
    func testMoonDiscReadsAgainstThePage() {
        for theme in AppTheme.all {
            for (dark, p) in [(false, theme.light), (true, theme.dark)] {
                for phase in Event.EventType.allCases {
                    for hour in [8, 14, 19, 23] {
                        let aura = AuraPalette.make(phase: phase, theme: theme, isDark: dark, hour: hour)
                        let name = "\(theme.name) dark=\(dark) \(phase) \(hour)h"
                        XCTAssertGreaterThanOrEqual(contrast(aura.disc, p.page), 3.0, "\(name): disc on page")
                        XCTAssertGreaterThanOrEqual(contrast(aura.disc, aura.mesh[4]), 3.0, "\(name): disc on aura centre")
                    }
                }
            }
        }
    }

    // MARK: - Phase colours never come from the theme

    func testPhaseColorsIdenticalAcrossThemes() {
        useSharedThemeStore()
        let now = Date()
        AppGroup.defaults.set(now.addingTimeInterval(30 * 86_400), forKey: PersistenceKeys.plusExpiry)
        var seen: [[[Int]]] = []
        for theme in AppTheme.all {
            AppGroup.defaults.set(theme.id, forKey: DS.Theme.storageKey)
            XCTAssertEqual(DS.Theme.current.id, theme.id)
            let resolved = [DS.Color.phase1Default, DS.Color.phase2Default, DS.Color.phase3Default, DS.Color.phase4Default]
                .flatMap { [components($0, dark: false), components($0, dark: true)] }
            seen.append(resolved)
        }
        XCTAssertEqual(seen[0], [[201, 124, 124], [166, 96, 96], [124, 166, 140], [95, 138, 112],
                                 [201, 168, 124], [166, 136, 96], [140, 124, 166], [112, 95, 138]])
        for other in seen.dropFirst() { XCTAssertEqual(other, seen[0]) }
        // And the palette type has no phase slot at all.
        XCTAssertEqual(Mirror(reflecting: AppTheme.blush.light).children.map { $0.label ?? "" },
                       ["page", "card", "ink", "muted", "accent", "onAccent", "moon", "waveBack", "waveMid", "waveFront"])
    }

    // MARK: - Waves

    func testWaveColorsDerivedFromAccent() {
        XCTAssertEqual(RGB.mix(RGB(r: 0, g: 0, b: 0), RGB(r: 100, g: 200, b: 50), 0.5), RGB(r: 50, g: 100, b: 25))
        XCTAssertEqual(RGB.mix(RGB(r: 10, g: 10, b: 10), RGB(r: 20, g: 20, b: 20), 0), RGB(r: 10, g: 10, b: 10))
        XCTAssertEqual(RGB.mix(RGB(r: 10, g: 10, b: 10), RGB(r: 20, g: 20, b: 20), 1), RGB(r: 20, g: 20, b: 20))

        let steps = AppTheme.waveSteps
        XCTAssertGreaterThan(steps.back, steps.mid)
        XCTAssertGreaterThan(steps.mid, steps.front)
        XCTAssertGreaterThan(steps.front, 0)
        XCTAssertLessThan(steps.back, 1)

        for theme in AppTheme.all where theme.isPlus {
            for p in [theme.light, theme.dark] {
                XCTAssertEqual(p.waveBack, RGB.mix(p.accent, p.moon, steps.back), theme.id)
                XCTAssertEqual(p.waveMid, RGB.mix(p.accent, p.moon, steps.mid), theme.id)
                XCTAssertEqual(p.waveFront, RGB.mix(p.accent, p.moon, steps.front), theme.id)
                XCTAssertNotEqual(p.waveBack, p.waveFront, theme.id)
            }
        }
        // WaveBackground keeps its opacities.
        XCTAssertEqual(WaveBackground.opacities, [0.35, 0.50, 0.75])
    }

    func testTabBarAndWashTintsDeriveFromTheme() {
        let p = AppTheme.eclipse.light
        XCTAssertEqual(AppTheme.tabBar(p), RGB.mix(p.card, p.accent, 0.07))
        XCTAssertEqual(DS.Theme.washOpacity, 0.14, accuracy: 0.001)
    }

    /// Views redraw on a theme change only if the settings object announces it. `StartTabView` gives the
    /// tabs the effective theme id as their identity, so this announcement is what rebuilds them.
    func testChangingTheThemeAnnouncesAChangeToViewsObservingSettings() {
        let settings = AppSettings()
        let original = settings.themeID
        addTeardownBlock { settings.themeID = original }
        var announced = 0
        let sub = settings.objectWillChange.sink { announced += 1 }
        defer { sub.cancel() }

        settings.themeID = original == AppTheme.eclipse.id ? AppTheme.blueMoon.id : AppTheme.eclipse.id

        XCTAssertGreaterThan(announced, 0)
    }
}
