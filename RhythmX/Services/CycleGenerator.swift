//  CycleGenerator.swift

import Foundation

enum CycleGenerator {
    /// Day-offset ranges per phase. Same layout the app has always generated.
    static func phaseRanges(cycleLength: Int) -> [(Event.EventType, Range<Int>)] {
        [
            (.menstrual,  0..<5),
            (.follicular, 5..<13),
            (.ovulation,  13..<16),
            (.luteal,     16..<max(16, cycleLength))
        ]
    }

    static func events(startDate: Date, cycleLength: Int = 28) -> [Event] {
        var result: [Event] = []
        for (phase, range) in phaseRanges(cycleLength: cycleLength) {
            for offset in range {
                guard let date = Calendar.current.date(byAdding: .day, value: offset, to: startDate) else { continue }
                result.append(Event(
                    eventType: phase,
                    date: date,
                    note: "\(phase.rawValue.capitalized) day \(offset + 1)"
                ))
            }
        }
        return result
    }

    static func dayCounts(cycleLength: Int) -> [Event.EventType: Int] {
        var counts: [Event.EventType: Int] = [:]
        for (phase, range) in phaseRanges(cycleLength: cycleLength) { counts[phase] = range.count }
        return counts
    }
}
