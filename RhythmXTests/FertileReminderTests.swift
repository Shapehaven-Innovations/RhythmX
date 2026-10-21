import XCTest
import UserNotifications
@testable import RhythmX

/// Fertile window reminders: computed from `FertileWindow` on cycle events, never in Menopause mode,
/// never in the past, always labelled as estimates.
final class FertileReminderTests: XCTestCase {
    private let calendar = Calendar.current
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 9))! }
    private func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: calendar.startOfDay(for: now))! }
    /// 8:00 local on day `n` (not start of day plus eight hours, which drifts across a DST change).
    private func eight(_ n: Int) -> Date { calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day(n))! }

    private let startID = "rhythmx.fertile.start"
    private let ovulationID = "rhythmx.fertile.ovulation"

    // MARK: - Fixtures

    /// A generated cycle starting `offset` days from now: fertile window opens on day 8, ovulation on day 13.
    private func cycle(startingIn offset: Int) -> [Event] {
        CycleGenerator.events(startDate: day(offset), cycleLength: 28)
    }

    private func dates(for events: [Event]) -> (window: ClosedRange<Date>?, ovulation: Date?) {
        NotificationScheduler.fertileDates(events: events, overrides: FertileOverrides(), calendar: calendar)
    }

    private func requests(events: [Event], mode: TrackingMode = .cycle, startOn: Bool = true, ovulationOn: Bool = true) -> [UNNotificationRequest] {
        let d = dates(for: events)
        return NotificationScheduler.fertileRequests(window: d.window, ovulation: d.ovulation,
                                                     startOn: startOn, ovulationOn: ovulationOn, mode: mode, now: now)
    }

    private func fireDate(_ request: UNNotificationRequest, file: StaticString = #filePath, line: UInt = #line) throws -> Date {
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger, file: file, line: line)
        XCTAssertFalse(trigger.repeats, file: file, line: line)
        return try XCTUnwrap(calendar.date(from: trigger.dateComponents), file: file, line: line)
    }

    // MARK: - Tests

    func testFertileRequestsNeverScheduledInMenopauseMode() {
        let events = cycle(startingIn: 2)
        XCTAssertEqual(requests(events: events, mode: .cycle).count, 2, "sanity: the same data schedules in Cycle")
        XCTAssertEqual(requests(events: events, mode: .planning).count, 2)
        XCTAssertEqual(requests(events: events, mode: .menopause), [])
    }

    func testFertileDatesComeFromCycleEventsOnly() throws {
        let events = cycle(startingIn: 2)
        // A menopause entry logged as an ovulation-phase day far in the future must not move the window.
        let stray = Event(id: "M-1", eventType: .ovulation, date: day(60), note: "", tags: "Menopause: Hot Flashes", mode: .menopause)

        let clean = dates(for: events)
        let mixed = dates(for: events + [stray])

        XCTAssertEqual(mixed.window, clean.window)
        XCTAssertEqual(mixed.ovulation, clean.ovulation)
        XCTAssertEqual(try XCTUnwrap(clean.window).lowerBound, day(2 + 8))
        XCTAssertEqual(clean.ovulation, day(2 + 13))
    }

    func testFertileRequestsRescheduledWhenEventsChange() throws {
        let before = requests(events: cycle(startingIn: 2))
        let after = requests(events: cycle(startingIn: 9))

        // Same identifiers both times, so re-adding replaces the earlier request...
        XCTAssertEqual(before.map(\.identifier), [startID, ovulationID])
        XCTAssertEqual(after.map(\.identifier), [startID, ovulationID])
        // ...and the scheduler cancels exactly those identifiers before adding.
        XCTAssertEqual(Set(NotificationScheduler.fertileIdentifiers), [startID, ovulationID])

        // Different events give different fire dates.
        XCTAssertEqual(try fireDate(before[0]), eight(10))
        XCTAssertEqual(try fireDate(after[0]), eight(17))
        XCTAssertEqual(try fireDate(before[1]), eight(15))
        XCTAssertEqual(try fireDate(after[1]), eight(22))
    }

    func testFertileRequestsNeverInThePast() throws {
        // Whole cycle in the past: nothing.
        XCTAssertEqual(requests(events: cycle(startingIn: -60)), [])

        // Window opened yesterday, ovulation still ahead: only the ovulation reminder.
        let partlyPast = requests(events: cycle(startingIn: -9))
        XCTAssertEqual(partlyPast.map(\.identifier), [ovulationID])
        XCTAssertGreaterThan(try fireDate(partlyPast[0]), now)

        // Window opens today at 8:00, but it is already 9:00: the start reminder would be in the past.
        let today = requests(events: cycle(startingIn: -8))
        XCTAssertEqual(today.map(\.identifier), [ovulationID])

        // A nil window and nil ovulation schedule nothing.
        XCTAssertEqual(NotificationScheduler.fertileRequests(window: nil, ovulation: nil, startOn: true, ovulationOn: true, mode: .cycle, now: now), [])

        for request in requests(events: cycle(startingIn: 1)) {
            XCTAssertGreaterThan(try fireDate(request), now)
        }
    }

    func testFertileBodyEndsWithEstimatesOnly() {
        let all = requests(events: cycle(startingIn: 3))
        XCTAssertEqual(all.count, 2)
        for request in all {
            XCTAssertTrue(request.content.body.hasSuffix("Estimates only."), request.content.body)
            XCTAssertFalse(request.content.body.isEmpty)
            XCTAssertFalse(request.content.title.isEmpty)
        }
    }

    func testFertileIdentifiers() throws {
        let all = requests(events: cycle(startingIn: 3))
        XCTAssertEqual(all.map(\.identifier), [startID, ovulationID])

        let trigger = try XCTUnwrap(all[0].trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 8)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }

    func testFertileTogglesSelectRequests() {
        let events = cycle(startingIn: 3)
        XCTAssertEqual(requests(events: events, startOn: true, ovulationOn: false).map(\.identifier), [startID])
        XCTAssertEqual(requests(events: events, startOn: false, ovulationOn: true).map(\.identifier), [ovulationID])
        XCTAssertEqual(requests(events: events, startOn: false, ovulationOn: false), [])
    }

    /// The period reminder identifiers and API are untouched by this task.
    func testPeriodReminderIdentifiersUnchanged() {
        XCTAssertEqual(NotificationScheduler.cycleIdentifiers, ["rhythmx.cycle.daybefore", "rhythmx.cycle.dayof"])
    }
}
