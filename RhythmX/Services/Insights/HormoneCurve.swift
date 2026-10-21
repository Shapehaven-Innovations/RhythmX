//  HormoneCurve.swift
//  The "Where you are" chart in a daily insight: typical estrogen, progesterone and LH curves across a cycle,
//  with a marker at today. A textbook-style pattern, never measured from the person's body and never medical
//  advice; the chart says "Typical pattern, estimates only". Pure and deterministic.
//
//  The curves are drawn on a 28-day template. The app's own phase layout (CycleGenerator) keeps the menstrual,
//  follicular and ovulation days fixed (days 1 to 16) and lets the luteal phase take the rest, so a cycle of
//  another length maps days 1 to 16 unchanged and stretches or squeezes days 17 to the end onto 17 to 28.

import Foundation

enum HormoneCurve {
    enum Hormone: CaseIterable {
        case estrogen, progesterone, lh
    }

    struct Sample: Equatable {
        let day: Double
        let estrogen: Double
        let progesterone: Double
        let lh: Double

        func value(_ hormone: Hormone) -> Double {
            switch hormone {
            case .estrogen:     return estrogen
            case .progesterone: return progesterone
            case .lh:           return lh
            }
        }
    }

    /// Today on the progesterone curve (the line the marker rides).
    struct Marker: Equatable {
        let day: Int
        let level: Double
        /// 0 at day 1, 1 at the last day.
        let xFraction: Double
    }

    static let minLength = 20
    static let maxLength = 45
    static let samplesPerDay = 4
    /// Days 1 to `fixedDays` are the same in every cycle length.
    static let fixedDays = 16.0
    static let templateLength = 28.0

    static func clampedLength(_ length: Int) -> Int { min(max(length, minLength), maxLength) }

    /// The 28-day template day for `day` of a cycle of `length` days.
    static func templateDay(_ day: Double, length: Int) -> Double {
        let length = Double(clampedLength(length))
        guard day > fixedDays else { return day }
        return fixedDays + (day - fixedDays) * (templateLength - fixedDays) / (length - fixedDays)
    }

    private static func bump(_ d: Double, center: Double, width: Double) -> Double {
        exp(-pow((d - center) / width, 2))
    }

    /// Level 0 to 100 (relative, not a unit).
    static func level(_ hormone: Hormone, day: Double, length: Int) -> Double {
        let d = templateDay(day, length: length)
        let value: Double
        switch hormone {
        case .estrogen:     value = 16 + 40 * bump(d, center: 13, width: 2.6) + 18 * bump(d, center: 21, width: 3.5)
        case .progesterone: value = 6 + 70 * bump(d, center: 21, width: 3.6)
        case .lh:           value = 4 + 92 * bump(d, center: 13.6, width: 0.9)
        }
        return min(max(value, 0), 100)
    }

    /// Day 1 to the last day, `samplesPerDay` points a day.
    static func samples(length: Int) -> [Sample] {
        let length = clampedLength(length)
        let count = (length - 1) * samplesPerDay
        return (0...count).map { i in
            let day = 1 + Double(i) / Double(samplesPerDay)
            return Sample(day: day,
                          estrogen: level(.estrogen, day: day, length: length),
                          progesterone: level(.progesterone, day: day, length: length),
                          lh: level(.lh, day: day, length: length))
        }
    }

    static func marker(day: Int, length: Int) -> Marker {
        let length = clampedLength(length)
        let day = min(max(day, 1), length)
        return Marker(day: day, level: level(.progesterone, day: Double(day), length: length),
                      xFraction: Double(day - 1) / Double(length - 1))
    }

    /// The typical fertile window in cycle days: the ovulation phase days and the five days before the first
    /// of them, as `FertileWindow.autoDays` marks them.
    static func fertileBand(length: Int) -> ClosedRange<Double> {
        let ovulation = CycleGenerator.phaseRanges(cycleLength: clampedLength(length)).first { $0.0 == .ovulation }?.1 ?? 13..<16
        let first = Double(ovulation.lowerBound + 1)
        return (first - Double(FertileWindow.daysBeforeOvulation))...Double(ovulation.upperBound)
    }

    /// The chart read aloud (VoiceOver).
    static func summary(day: Int, length: Int) -> String {
        let marker = marker(day: day, length: length)
        let d = templateDay(Double(marker.day), length: length)
        let state: String
        switch d {
        case ..<6:   state = "hormones are usually low."
        case ..<13:  state = "estrogen is usually rising."
        case ..<17:  state = "LH and estrogen usually peak around now."
        case ..<21:  state = "progesterone is usually rising."
        default:     state = "progesterone is usually falling."
        }
        return "Typical pattern, estimates only. Day \(marker.day) of \(clampedLength(length)): \(state)"
    }

    /// The four phases as day ranges (1-based, inclusive), for the coloured bars under the curves.
    static func phaseBands(length: Int) -> [(phase: Event.EventType, days: ClosedRange<Int>)] {
        CycleGenerator.phaseRanges(cycleLength: clampedLength(length)).compactMap { phase, range in
            range.isEmpty ? nil : (phase, (range.lowerBound + 1)...range.upperBound)
        }
    }
}
