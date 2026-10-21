import XCTest
@testable import RhythmX

final class GreetingProviderTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func at(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: hour, minute: minute))!
    }

    private func text(_ hour: Int, _ minute: Int, _ style: GreetingStyle = .greeting, name: String = "") -> String? {
        GreetingProvider.text(now: at(hour, minute), style: style, name: name, calendar: calendar)
    }

    func testMorningBoundaries() {
        XCTAssertEqual(text(5, 0), "Good morning")
        XCTAssertEqual(text(11, 59), "Good morning")
    }

    func testAfternoonBoundaries() {
        XCTAssertEqual(text(12, 0), "Good afternoon")
        XCTAssertEqual(text(16, 59), "Good afternoon")
    }

    func testEveningBoundariesWrapPastMidnight() {
        XCTAssertEqual(text(17, 0), "Good evening")
        XCTAssertEqual(text(23, 59), "Good evening")
        XCTAssertEqual(text(0, 0), "Good evening")
        XCTAssertEqual(text(4, 59), "Good evening")
    }

    func testNameStyleAddsTheTrimmedName() {
        XCTAssertEqual(text(9, 0, .name, name: "  Ana "), "Good morning, Ana")
        XCTAssertEqual(text(13, 0, .name, name: "Sam"), "Good afternoon, Sam")
    }

    func testNameStyleWithoutANameIsThePlainGreeting() {
        XCTAssertEqual(text(18, 0, .name, name: "   "), "Good evening")
    }

    func testGreetingStyleIgnoresTheName() {
        XCTAssertEqual(text(9, 0, .greeting, name: "Ana"), "Good morning")
    }

    func testOffIsNil() {
        XCTAssertNil(text(9, 0, .off, name: "Ana"))
    }

    func testOnlyTheThreeGreetingsEverAppear() {
        let allowed: Set<String> = ["Good morning", "Good afternoon", "Good evening"]
        for hour in 0..<24 {
            for minute in stride(from: 0, to: 60, by: 15) {
                XCTAssertTrue(allowed.contains(text(hour, minute) ?? ""), "\(hour):\(minute)")
            }
        }
    }

    func testStoredStyleDefaultsAndUnknownValues() {
        XCTAssertEqual(GreetingStyle(stored: "name"), .name)
        XCTAssertEqual(GreetingStyle(stored: "off"), .off)
        XCTAssertEqual(GreetingStyle(stored: "goddess"), .greeting, "unknown values fall back to the default")
        XCTAssertEqual(GreetingStyle.greeting.rawValue, "greeting")
    }

    func testAppSettingsKeysAreSharedWithTheWidget() {
        let key = AppSettings.greetingStyleKey
        let nameKey = AppSettings.greetingNameKey
        XCTAssertEqual(key, "greetingStyle")
        XCTAssertEqual(nameKey, "greetingName")
        let oldStyle = AppGroup.defaults.object(forKey: key)
        let oldName = AppGroup.defaults.object(forKey: nameKey)
        defer {
            AppGroup.defaults.set(oldStyle, forKey: key)
            AppGroup.defaults.set(oldName, forKey: nameKey)
        }
        AppGroup.defaults.removeObject(forKey: key)
        AppGroup.defaults.removeObject(forKey: nameKey)
        let settings = AppSettings()
        XCTAssertEqual(settings.greetingStyle, .greeting)
        XCTAssertEqual(settings.greetingName, "")
        settings.greetingStyle = .name
        settings.greetingName = "Ana"
        XCTAssertEqual(AppGroup.defaults.string(forKey: key), "name")
        XCTAssertEqual(AppGroup.defaults.string(forKey: nameKey), "Ana")
    }
}
