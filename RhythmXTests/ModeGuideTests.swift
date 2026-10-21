import XCTest
@testable import RhythmX

/// "Learn about phases" content for Planning and Menopause. Cycle mode keeps the four phase entries only.
final class ModeGuideTests: XCTestCase {

    func testCycleModeHasNoExtraGuideAndKeepsThePhaseEntries() {
        XCTAssertNil(ModeGuideContent.guide(for: .cycle))
        XCTAssertEqual(PhaseGuideContent.raw.count, 4)
    }

    func testEachOtherModeHasALabelledGuide() throws {
        let planning = try XCTUnwrap(ModeGuideContent.guide(for: .planning))
        let menopause = try XCTUnwrap(ModeGuideContent.guide(for: .menopause))
        XCTAssertEqual(planning.mode, .planning)
        XCTAssertEqual(menopause.mode, .menopause)
        XCTAssertEqual(planning.modeLabel, "Planning mode")
        XCTAssertEqual(menopause.modeLabel, "Menopause mode")
        for guide in [planning, menopause] {
            XCTAssertFalse(guide.intro.isEmpty)
            XCTAssertGreaterThanOrEqual(guide.topics.count, 4)
            XCTAssertEqual(guide.disclaimer, "Tracking tool, not medical advice.")
        }
    }

    func testEverySuggestedTagExistsInTheLibraryForItsCategory() throws {
        for mode in [TrackingMode.planning, .menopause] {
            let guide = try XCTUnwrap(ModeGuideContent.guide(for: mode))
            for topic in guide.topics {
                XCTAssertFalse(topic.tags.isEmpty, "\(topic.title) suggests tags")
                for tag in topic.tags {
                    XCTAssertTrue((TagLibrary.tags[tag.category] ?? []).contains(tag.value),
                                  "\(tag.raw) is not a library tag")
                }
            }
        }
    }

    func testPlanningCoversItsTopicsAndExplainsOvulationTests() throws {
        let guide = try XCTUnwrap(ModeGuideContent.guide(for: .planning))
        let titles = guide.topics.map(\.title)
        for expected in ["Fertile window", "Ovulation tests", "Basal temperature", "Cervical mucus", "Intercourse timing"] {
            XCTAssertTrue(titles.contains(expected), expected)
        }
        let tests = try XCTUnwrap(guide.topics.first { $0.title == "Ovulation tests" })
        XCTAssertEqual(tests.text, ModeGuideContent.ovulationTestExplanation)
        XCTAssertEqual(ModeGuideContent.ovulationTestExplanation,
                       "Ovulation tests are at-home test strips that detect the hormone surge that comes a day or two before ovulation. Log the result you see: Negative, Faint, Positive or Peak.")
        XCTAssertEqual(tests.tags.map(\.raw), ["Planning:Ovulation Test Negative", "Planning:Ovulation Test Faint",
                                               "Planning:Ovulation Test Positive", "Planning:Ovulation Test Peak"])
        let fertile = try XCTUnwrap(guide.topics.first { $0.title == "Fertile window" })
        XCTAssertTrue(fertile.text.contains("Predictions are estimates and are not birth control."))
    }

    func testMenopauseCoversItsTopics() throws {
        let guide = try XCTUnwrap(ModeGuideContent.guide(for: .menopause))
        let raws = guide.topics.flatMap(\.tags).map(\.raw)
        for expected in ["Menopause:Hot Flashes", "Menopause:Night Sweats", "Menopause:Poor Sleep", "Menopause:Brain Fog"] {
            XCTAssertTrue(raws.contains(expected), expected)
        }
        XCTAssertTrue(raws.contains { $0.hasPrefix("Mood:") }, "mood is covered")
    }

    func testCopyIsPlain() throws {
        for mode in [TrackingMode.planning, .menopause] {
            let guide = try XCTUnwrap(ModeGuideContent.guide(for: mode))
            let text = ([guide.title, guide.intro, guide.disclaimer] + guide.topics.flatMap { [$0.title, $0.text] })
                .joined(separator: " ")
            XCTAssertFalse(text.contains("\u{2014}"), "no em dashes")
        }
    }
}
