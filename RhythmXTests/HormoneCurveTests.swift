import XCTest
@testable import RhythmX

final class HormoneCurveTests: XCTestCase {

    func testSamplesAreDeterministicAndCoverTheWholeCycle() {
        let a = HormoneCurve.samples(length: 28)
        let b = HormoneCurve.samples(length: 28)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.first?.day, 1)
        XCTAssertEqual(a.last?.day, 28)
        XCTAssertEqual(a.count, 27 * HormoneCurve.samplesPerDay + 1)
    }

    func testLevelsStayBetweenZeroAndOneHundred() {
        for length in [20, 28, 35, 45] {
            for sample in HormoneCurve.samples(length: length) {
                for value in [sample.estrogen, sample.progesterone, sample.lh] {
                    XCTAssertGreaterThanOrEqual(value, 0)
                    XCTAssertLessThanOrEqual(value, 100)
                }
            }
        }
    }

    func testTwentyEightDayCycleUsesTheTemplateDaysUnchanged() {
        for day in stride(from: 1.0, through: 28.0, by: 0.5) {
            XCTAssertEqual(HormoneCurve.templateDay(day, length: 28), day, accuracy: 1e-9)
        }
    }

    func testFollicularDaysAreTheSameInEveryLengthAndTheLutealPhaseStretches() {
        XCTAssertEqual(HormoneCurve.templateDay(10, length: 35), 10, accuracy: 1e-9)
        XCTAssertEqual(HormoneCurve.templateDay(16, length: 35), 16, accuracy: 1e-9)
        XCTAssertEqual(HormoneCurve.templateDay(35, length: 35), 28, accuracy: 1e-9)
        XCTAssertEqual(HormoneCurve.templateDay(22, length: 22), 28, accuracy: 1e-9)
    }

    private func peakDay(_ hormone: HormoneCurve.Hormone, length: Int) -> Double {
        HormoneCurve.samples(length: length).max { $0.value(hormone) < $1.value(hormone) }!.day
    }

    func testLHPeaksJustBeforeTheOvulationDays() {
        XCTAssertEqual(peakDay(.lh, length: 28), 13.5, accuracy: 0.5)
        XCTAssertEqual(peakDay(.lh, length: 35), 13.5, accuracy: 0.5)
    }

    func testProgesteronePeaksMidLutealAndMovesLaterInALongerCycle() {
        XCTAssertEqual(peakDay(.progesterone, length: 28), 21, accuracy: 0.5)
        XCTAssertGreaterThan(peakDay(.progesterone, length: 35), 23)
    }

    func testEstrogenRisesBeforeOvulation() {
        XCTAssertGreaterThan(HormoneCurve.level(.estrogen, day: 13, length: 28),
                             HormoneCurve.level(.estrogen, day: 3, length: 28) + 30)
    }

    func testMarkerSitsOnTheProgesteroneCurveAtToday() {
        let marker = HormoneCurve.marker(day: 26, length: 28)
        XCTAssertEqual(marker.day, 26)
        XCTAssertEqual(marker.level, HormoneCurve.level(.progesterone, day: 26, length: 28), accuracy: 1e-9)
        XCTAssertEqual(marker.xFraction, 25.0 / 27.0, accuracy: 1e-9)
    }

    func testMarkerIsClampedIntoTheCycle() {
        XCTAssertEqual(HormoneCurve.marker(day: 0, length: 28).day, 1)
        XCTAssertEqual(HormoneCurve.marker(day: 40, length: 28).day, 28)
        XCTAssertEqual(HormoneCurve.marker(day: 40, length: 28).xFraction, 1, accuracy: 1e-9)
    }

    func testLengthIsClampedToTheSupportedRange() {
        XCTAssertEqual(HormoneCurve.clampedLength(10), 20)
        XCTAssertEqual(HormoneCurve.clampedLength(60), 45)
        XCTAssertEqual(HormoneCurve.samples(length: 10).last?.day, 20)
    }

    func testFertileBandMatchesTheAppsFertileWindow() {
        // Ovulation phase days 14 to 16, and five days before the first of them (FertileWindow.autoDays).
        XCTAssertEqual(HormoneCurve.fertileBand(length: 28), 9...16)
        XCTAssertEqual(HormoneCurve.fertileBand(length: 35), 9...16)
    }

    func testVoiceOverSummarySaysWhereTodayIsInPlainWords() {
        XCTAssertEqual(HormoneCurve.summary(day: 26, length: 28),
                       "Typical pattern, estimates only. Day 26 of 28: progesterone is usually falling.")
        XCTAssertTrue(HormoneCurve.summary(day: 3, length: 28).hasSuffix("hormones are usually low."))
        XCTAssertTrue(HormoneCurve.summary(day: 10, length: 28).hasSuffix("estrogen is usually rising."))
        XCTAssertTrue(HormoneCurve.summary(day: 14, length: 28).hasSuffix("LH and estrogen usually peak around now."))
        XCTAssertTrue(HormoneCurve.summary(day: 19, length: 28).hasSuffix("progesterone is usually rising."))
        XCTAssertTrue(HormoneCurve.summary(day: 30, length: 35).hasSuffix("progesterone is usually falling."))
    }

    func testPhaseBandsFollowTheGeneratorAndCoverEveryDay() {
        let bands = HormoneCurve.phaseBands(length: 30)
        XCTAssertEqual(bands.map(\.phase), [.menstrual, .follicular, .ovulation, .luteal])
        XCTAssertEqual(bands.first?.days.lowerBound, 1)
        XCTAssertEqual(bands.last?.days.upperBound, 30)
        for (a, b) in zip(bands, bands.dropFirst()) {
            XCTAssertEqual(a.days.upperBound + 1, b.days.lowerBound)
        }
    }
}
