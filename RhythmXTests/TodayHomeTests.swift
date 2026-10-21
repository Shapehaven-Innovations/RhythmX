import XCTest
@testable import RhythmX

/// Step 4a: the pure models behind Today (moon phase name, week strip, hero copy per mode, Log Period).
final class TodayHomeTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    // MARK: - Lunar phase

    func testLunarPhaseNamesForKnownDates() {
        // 2026: first quarter Oct 18, full moon Oct 26, last quarter Nov 1, new moon Nov 9.
        XCTAssertEqual(LunarPhase.of(date(2026, 10, 20)), .waxingGibbous)
        XCTAssertEqual(LunarPhase.of(date(2026, 10, 26)), .fullMoon)
        XCTAssertEqual(LunarPhase.of(date(2026, 11, 9)), .newMoon)
        XCTAssertEqual(LunarPhase.of(date(2026, 10, 14)), .waxingCrescent)
        XCTAssertEqual(LunarPhase.of(date(2026, 10, 30)), .waningGibbous)
        XCTAssertEqual(LunarPhase.waxingGibbous.name, "Waxing gibbous")
    }

    func testLunarAgeStaysInsideTheMonth() {
        for offset in stride(from: -4000, through: 4000, by: 37) {
            let age = LunarPhase.age(at: date(2026, 1, 1).addingTimeInterval(Double(offset) * 86_400))
            XCTAssertGreaterThanOrEqual(age, 0)
            XCTAssertLessThan(age, LunarPhase.synodicMonth)
        }
    }

    // MARK: - Week strip

    func testWeekStripMarksPhasesTodayAndPredictedPeriod() {
        let today = date(2026, 10, 20)   // a Tuesday; the week is Sun 18 to Sat 24
        let events = [
            Event(eventType: .luteal, date: date(2026, 10, 18), note: ""),
            Event(eventType: .luteal, date: date(2026, 10, 19), note: ""),
            Event(eventType: .luteal, date: date(2026, 10, 20), note: ""),
        ]
        let days = TodayWeekStrip.days(events: events, today: today, mode: .cycle, nextPeriod: date(2026, 10, 23),
                                       periodLength: 5, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(calendar.component(.day, from: days[0].date), 18)
        XCTAssertEqual(days.map(\.isToday), [false, false, true, false, false, false, false])
        XCTAssertEqual(days[0].phase, .luteal)
        XCTAssertNil(days[3].phase)
        XCTAssertEqual(days.map(\.isPredictedPeriod), [false, false, false, false, false, true, true])
    }

    func testWeekStripNeverShowsMenopauseAsPhaseOrPrediction() {
        let today = date(2026, 10, 20)
        let events = [
            Event(eventType: .follicular, date: date(2026, 10, 19), note: "", tags: "Menopause:Hot Flashes, Menopause:Hot Flashes", mode: .menopause),
            Event(eventType: .luteal, date: date(2026, 10, 20), note: ""),
        ]
        let cycle = TodayWeekStrip.days(events: events, today: today, mode: .cycle, nextPeriod: nil, periodLength: 5, calendar: calendar)
        XCTAssertNil(cycle[1].phase, "a menopause entry is not a phase")
        XCTAssertEqual(cycle[2].phase, .luteal)

        let meno = TodayWeekStrip.days(events: events, today: today, mode: .menopause, nextPeriod: date(2026, 10, 23),
                                       periodLength: 5, calendar: calendar)
        XCTAssertTrue(meno.allSatisfy { $0.phase == nil && !$0.isPredictedPeriod })
        XCTAssertEqual(meno[1].menopauseCount, 2)
    }

    // MARK: - Hero

    private func snapshot(phase: Event.EventType? = .luteal, day: Int? = 26, until: Int? = 3, overdue: Int? = nil,
                          next: Date? = nil, fertileToday: Bool = false, endsIn: Int? = nil, startsIn: Int? = nil) -> PhaseWidgetSnapshot {
        PhaseWidgetSnapshot(phase: phase, cycleDay: day, daysUntilNext: until, overdueDays: overdue,
                            nextPeriodDate: next, isFertileToday: fertileToday, fertileEndsIn: endsIn, fertileStartsIn: startsIn)
    }

    func testCycleHeroCountsDownToThePeriod() {
        let hero = TodayHero.make(mode: .cycle, snapshot: snapshot(next: date(2026, 10, 23)), today: date(2026, 10, 20), calendar: calendar)
        XCTAssertEqual(hero.eyebrow, "Luteal · Day 26")
        XCTAssertEqual(hero.lead, "Period in")
        XCTAssertEqual(hero.headline, "3 days")
        XCTAssertEqual(hero.detail, "Expected Fri, Oct 23")
        XCTAssertEqual(hero.action, .logPeriod)
        XCTAssertEqual(hero.action.title, "Log Period")
        XCTAssertFalse(hero.isFertilityEstimate)
    }

    func testCycleHeroSingularTodayAndLate() {
        XCTAssertEqual(TodayHero.make(mode: .cycle, snapshot: snapshot(until: 1), today: date(2026, 10, 20), calendar: calendar).headline, "1 day")
        XCTAssertEqual(TodayHero.make(mode: .cycle, snapshot: snapshot(until: 0), today: date(2026, 10, 20), calendar: calendar).headline, "Today")
        let late = TodayHero.make(mode: .cycle, snapshot: snapshot(until: nil, overdue: 2), today: date(2026, 10, 20), calendar: calendar)
        XCTAssertEqual(late.headline, "2 days late")
    }

    func testHeroWithoutACycleInvitesTheFirstPeriod() {
        let hero = TodayHero.make(mode: .cycle, snapshot: snapshot(phase: nil, day: nil, until: nil), today: date(2026, 10, 20), calendar: calendar)
        XCTAssertEqual(hero.headline, "Day 1")
        XCTAssertEqual(hero.action, .logPeriod)
    }

    func testPlanningHeroShowsTheNextWindowWithBestChances() {
        // Window Oct 31 to Nov 5 (five days before ovulation on Nov 5, plus the day itself).
        var keys = Set<String>()
        for d in 0..<6 { keys.insert(FertileWindow.dayKey(calendar.date(byAdding: .day, value: d, to: date(2026, 10, 31))!, calendar: calendar)) }
        let hero = TodayHero.make(mode: .planning, snapshot: snapshot(startsIn: 11), fertileDays: keys,
                                  today: date(2026, 10, 20), calendar: calendar)
        XCTAssertEqual(hero.lead, "Fertile window in")
        XCTAssertEqual(hero.headline, "11 days")
        XCTAssertEqual(hero.detail, "Best chances around Nov 4 and 5")
        XCTAssertEqual(hero.action.title, "Log Test")
        XCTAssertTrue(hero.isFertilityEstimate)
    }

    func testPlanningHeroInsideTheWindow() {
        let hero = TodayHero.make(mode: .planning, snapshot: snapshot(fertileToday: true, endsIn: 2), today: date(2026, 10, 20), calendar: calendar)
        XCTAssertEqual(hero.lead, "Fertile window")
        XCTAssertEqual(hero.headline, "Today")
        XCTAssertEqual(hero.detail, "Ends in 2 days")
        XCTAssertTrue(hero.isFertilityEstimate)
    }

    func testPlanningHeroFallsBackToThePeriodWithoutAnUpcomingWindow() {
        let hero = TodayHero.make(mode: .planning, snapshot: snapshot(), today: date(2026, 10, 20), calendar: calendar)
        XCTAssertEqual(hero.lead, "Period in")
        XCTAssertEqual(hero.action, .logTest)
        XCTAssertFalse(hero.isFertilityEstimate)
    }

    func testMenopauseHeroComparesHotFlashWeeks() {
        let down = TodayHero.make(mode: .menopause, snapshot: snapshot(), hotFlashes: (9, 14), today: date(2026, 10, 20), calendar: calendar)
        XCTAssertEqual(down.eyebrow, "This week")
        XCTAssertEqual(down.lead, "Hot flashes")
        XCTAssertEqual(down.headline, "9")
        XCTAssertEqual(down.detail, "Down from 14 last week")
        XCTAssertEqual(down.action.title, "Log Symptoms")
        XCTAssertEqual(TodayHero.make(mode: .menopause, snapshot: snapshot(), hotFlashes: (5, 2), today: date(2026, 10, 20)).detail,
                       "Up from 2 last week")
        XCTAssertEqual(TodayHero.make(mode: .menopause, snapshot: snapshot(), hotFlashes: (3, 3), today: date(2026, 10, 20)).detail,
                       "Same as last week")
    }

    func testHeroCopyHasNoDashesOrBannedWords() {
        let heroes = [
            TodayHero.make(mode: .cycle, snapshot: snapshot(), today: date(2026, 10, 20), calendar: calendar),
            TodayHero.make(mode: .planning, snapshot: snapshot(fertileToday: true, endsIn: 0), today: date(2026, 10, 20), calendar: calendar),
            TodayHero.make(mode: .menopause, snapshot: snapshot(), hotFlashes: (0, 0), today: date(2026, 10, 20), calendar: calendar),
        ]
        for hero in heroes {
            let text = [hero.eyebrow, hero.lead, hero.headline, hero.detail ?? ""].joined(separator: " ")
            XCTAssertFalse(text.contains("\u{2014}"), text)
            XCTAssertFalse(text.lowercased().contains("goddess"), text)
        }
    }

    // MARK: - Menopause week

    func testMenopauseDailyCountsLastSevenDaysOldestFirst() {
        let today = date(2026, 10, 20)
        let events = [
            Event(eventType: .follicular, date: today, note: "", tags: "Menopause:Hot Flashes", mode: .menopause),
            Event(eventType: .follicular, date: date(2026, 10, 14), note: "", tags: "Menopause:Hot Flashes, Menopause:Night Sweats", mode: .menopause),
            Event(eventType: .follicular, date: date(2026, 10, 13), note: "", tags: "Menopause:Hot Flashes", mode: .menopause),
            Event(eventType: .luteal, date: today, note: "", tags: "Symptom:Cramps"),
        ]
        XCTAssertEqual(TodayMenopauseWeek.dailyCounts(events: events, today: today, calendar: calendar), [2, 0, 0, 0, 0, 0, 1])
    }

    // MARK: - Log Period

    func testPeriodStartArchivesPastDaysAndStartsANewCycleToday() {
        let today = date(2026, 10, 20, hour: 0)
        var old = CycleGenerator.events(startDate: date(2026, 9, 25, hour: 0), cycleLength: 28)   // day 26 today
        let todayIndex = old.firstIndex { calendar.isDate($0.date, inSameDayAs: today) }!
        old[todayIndex].tags = "Symptom:Bloating"
        old[todayIndex].mode = .cycle
        let meno = Event(eventType: .follicular, date: date(2026, 10, 1), note: "", tags: "Menopause:Hot Flashes", mode: .menopause)
        let plan = PeriodStartPlan.make(events: old + [meno], today: today, cycleLength: 28, calendar: calendar)

        XCTAssertEqual(plan.archive.count, 25, "days 1 to 25 move to Past cycles")
        XCTAssertTrue(plan.archive.allSatisfy { $0.date < today })
        XCTAssertTrue(plan.events.contains { $0.id == meno.id }, "menopause entries stay")
        let cycle = plan.events.filter { $0.effectiveMode != .menopause }
        XCTAssertEqual(cycle.count, 28)
        let first = cycle.min { $0.date < $1.date }!
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: today))
        XCTAssertEqual(first.eventType, .menstrual)
        XCTAssertEqual(first.tags, "Symptom:Bloating", "today's tags carry over to day 1")
        XCTAssertFalse(plan.events.contains { $0.id == old[todayIndex].id })
    }

    func testPeriodStartKeepsTheModeOfCarriedTags() {
        let today = date(2026, 10, 20, hour: 0)
        var old = CycleGenerator.events(startDate: date(2026, 9, 25, hour: 0), cycleLength: 28)
        let todayIndex = old.firstIndex { calendar.isDate($0.date, inSameDayAs: today) }!
        old[todayIndex].tags = "Planning:Ovulation Test Negative"
        old[todayIndex].mode = .planning
        let plan = PeriodStartPlan.make(events: old, today: today, cycleLength: 28, calendar: calendar)
        let first = plan.events.min { $0.date < $1.date }!
        XCTAssertEqual(first.mode, .planning, "a Planning tag stays a Planning tag")
    }

    func testPeriodStartCombinesSameDayEventsInsteadOfOverwriting() {
        let today = date(2026, 10, 20, hour: 0)
        var old = CycleGenerator.events(startDate: date(2026, 9, 25, hour: 0), cycleLength: 28)
        let todayIndex = old.firstIndex { calendar.isDate($0.date, inSameDayAs: today) }!
        old[todayIndex].tags = "Symptom:Cramps"
        old[todayIndex].mode = .cycle
        old[todayIndex].tagIntensity = ["Symptom:Cramps": 3]
        // A second event on the same day (for example a Planning entry) with its own tags and levels.
        let second = Event(eventType: .luteal, date: today.addingTimeInterval(3600), note: "",
                           tags: "Mood:Calm, Symptom:Cramps", mode: .cycle,
                           tagIntensity: ["Mood:Calm": 1, "Symptom:Cramps": 1])
        let plan = PeriodStartPlan.make(events: old + [second], today: today, cycleLength: 28, calendar: calendar)
        let todays = plan.events.filter { calendar.isDate($0.date, inSameDayAs: today) }
        XCTAssertEqual(todays.count, 1, "one day 1")
        let first = todays[0]
        XCTAssertEqual(first.eventType, .menstrual)
        XCTAssertEqual(Set(TagParser.split(first.tags)), ["Symptom:Cramps", "Mood:Calm"], "both events' tags are kept, once each")
        XCTAssertEqual(first.tagIntensity, ["Symptom:Cramps": 3, "Mood:Calm": 1], "levels kept, the higher one wins")
        XCTAssertEqual(first.mode, .cycle)
    }

    func testPeriodStartKeepsCarriedTagsPastTheNewCycleLength() {
        let today = date(2026, 10, 20, hour: 0)
        let old = CycleGenerator.events(startDate: date(2026, 10, 18, hour: 0), cycleLength: 40)
        var events = old
        // Day 30 after today: past a 28 day cycle, so no generated day matches it.
        let farIndex = events.firstIndex { calendar.isDate($0.date, inSameDayAs: date(2026, 11, 19, hour: 0)) }!
        events[farIndex].tags = "Note:Trip"
        events[farIndex].tagIntensity = nil
        let plan = PeriodStartPlan.make(events: events, today: today, cycleLength: 28, calendar: calendar)
        let kept = plan.events.first { TagParser.split($0.tags).contains("Note:Trip") }
        XCTAssertNotNil(kept, "a carried tag past the new cycle length is not dropped")
        XCTAssertTrue(calendar.isDate(kept!.date, inSameDayAs: date(2026, 11, 19, hour: 0)), "it stays on its own day")
    }

    // MARK: - Move the period start

    func testMoveStartIsOfferedOnlyEarlyInACycle() {
        XCTAssertFalse(PeriodStartPlan.offersMoveStart(cycleDay: nil))
        XCTAssertFalse(PeriodStartPlan.offersMoveStart(cycleDay: 1))
        XCTAssertTrue(PeriodStartPlan.offersMoveStart(cycleDay: 2))
        XCTAssertTrue(PeriodStartPlan.offersMoveStart(cycleDay: 14))
        XCTAssertFalse(PeriodStartPlan.offersMoveStart(cycleDay: 15))
    }

    func testLogPeriodConfirmationSaysWhatHappens() {
        let early = PeriodStartPlan.confirmationMessage(cycleDay: 3)
        XCTAssertTrue(early.contains("2 days ago"), early)
        XCTAssertTrue(early.contains("move it to today"), early)
        let late = PeriodStartPlan.confirmationMessage(cycleDay: 26)
        XCTAssertTrue(late.contains("move to Past cycles"), late)
        XCTAssertTrue(late.contains("Tags you logged today stay"), late)
        for text in [early, late, PeriodStartPlan.confirmationMessage(cycleDay: nil)] {
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}") || text.contains("--"), text)
        }
    }

    func testMoveStartReanchorsTheCycleWithoutArchivingATinyCycle() {
        let today = date(2026, 10, 20, hour: 0)
        let start = date(2026, 10, 17, hour: 0)   // day 4 today
        var current = CycleGenerator.events(startDate: start, cycleLength: 28)
        let tagged = current.firstIndex { calendar.isDate($0.date, inSameDayAs: date(2026, 10, 18, hour: 0)) }!
        current[tagged].tags = "Mood:Tired"
        let todayIndex = current.firstIndex { calendar.isDate($0.date, inSameDayAs: today) }!
        current[todayIndex].tags = "Symptom:Cramps"
        let meno = Event(eventType: .follicular, date: date(2026, 10, 18), note: "", tags: "Menopause:Hot Flashes", mode: .menopause)
        // The cycle before ended the day before the mistaken start.
        let prevEvents = CycleGenerator.events(startDate: date(2026, 9, 19, hour: 0), cycleLength: 28)
        let previous = ArchivedDataBlock(date: date(2026, 10, 17), groupedEvents: Dictionary(grouping: prevEvents, by: \.eventType)
            .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) })

        let plan = PeriodStartPlan.moveStart(events: current + [meno], blocks: [previous], today: today,
                                             cycleLength: 28, calendar: calendar)
        let cycle = plan.events.filter { $0.effectiveMode != .menopause }
        XCTAssertEqual(cycle.count, 28)
        let first = cycle.min { $0.date < $1.date }!
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: today), "the cycle now starts today")
        XCTAssertEqual(first.eventType, .menstrual)
        XCTAssertEqual(first.tags, "Symptom:Cramps")
        XCTAssertTrue(plan.events.contains { $0.id == meno.id })
        XCTAssertTrue(plan.newArchive.isEmpty, "no new Past cycle")

        // The days before today join the cycle before, so its length is right and no tag is lost.
        let blocks = try! XCTUnwrap(plan.blocks)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].id, previous.id)
        let all = blocks[0].groupedEvents.flatMap(\.events)
        XCTAssertEqual(all.count, prevEvents.count + 3)
        XCTAssertTrue(all.contains { $0.tags == "Mood:Tired" && $0.eventType == .luteal })
        XCTAssertEqual(CyclePredictionService.predictedStartDate(from: blocks).map { calendar.startOfDay(for: $0) },
                       calendar.date(byAdding: .day, value: 31, to: date(2026, 9, 19, hour: 0)),
                       "the previous cycle is now 31 days long")
    }

    func testMoveStartWithNoCycleBeforeKeepsOnlyTaggedDays() {
        let today = date(2026, 10, 20, hour: 0)
        var current = CycleGenerator.events(startDate: date(2026, 10, 17, hour: 0), cycleLength: 28)
        let plain = PeriodStartPlan.moveStart(events: current, blocks: [], today: today, cycleLength: 28, calendar: calendar)
        XCTAssertNil(plain.blocks)
        XCTAssertTrue(plain.newArchive.isEmpty, "untagged days before today are simply dropped")

        let tagged = current.firstIndex { calendar.isDate($0.date, inSameDayAs: date(2026, 10, 18, hour: 0)) }!
        current[tagged].tags = "Mood:Tired"
        let plan = PeriodStartPlan.moveStart(events: current, blocks: [], today: today, cycleLength: 28, calendar: calendar)
        XCTAssertEqual(plan.newArchive.map(\.tags), ["Mood:Tired"], "a tag is never lost")
        XCTAssertFalse(plan.events.contains { $0.date < today }, "nothing before today stays in the current cycle")
    }

    // MARK: - Ambient motion

    func testAmbientMotionRunsOnlyWhenSeenActiveAndAllowed() {
        XCTAssertTrue(AmbientMotion.isOn(reduceMotion: false, lowPower: false, active: true, visible: true))
        XCTAssertFalse(AmbientMotion.isOn(reduceMotion: true, lowPower: false, active: true, visible: true))
        XCTAssertFalse(AmbientMotion.isOn(reduceMotion: false, lowPower: true, active: true, visible: true))
        XCTAssertFalse(AmbientMotion.isOn(reduceMotion: false, lowPower: false, active: false, visible: true))
        XCTAssertFalse(AmbientMotion.isOn(reduceMotion: false, lowPower: false, active: true, visible: false))
        XCTAssertEqual(AmbientMotion.framesPerSecond, 15)
    }

    func testBreathingAndFloatAreStillWithoutAClock() {
        XCTAssertEqual(AmbientMotion.breath(at: nil), 0)
        XCTAssertEqual(AmbientMotion.floatOffset(index: 2, at: nil), 0)
        for t in stride(from: 0.0, to: 20, by: 0.37) {
            XCTAssertTrue((0...1).contains(AmbientMotion.breath(at: t)))
            XCTAssertTrue((-3...2).contains(AmbientMotion.floatOffset(index: 1, at: t)))
        }
    }

    func testAuraPhaseIsWorkedOutOncePerChangeAndNeverInMenopause() {
        let today = Date()
        let events = CycleGenerator.events(startDate: Calendar.current.date(byAdding: .day, value: -2, to: today.startOfDay)!,
                                           cycleLength: 28)
        XCTAssertEqual(StartTabView.auraPhase(mode: .cycle, events: events, archived: [], overrides: FertileOverrides(), today: today),
                       .menstrual)
        XCTAssertNil(StartTabView.auraPhase(mode: .menopause, events: events, archived: [], overrides: FertileOverrides(), today: today))
    }

    func testAlreadyStartedTodayDetection() {
        XCTAssertTrue(PeriodStartPlan.alreadyStartedToday(snapshot: snapshot(phase: .menstrual, day: 1)))
        XCTAssertFalse(PeriodStartPlan.alreadyStartedToday(snapshot: snapshot(phase: .menstrual, day: 2)))
    }
}
