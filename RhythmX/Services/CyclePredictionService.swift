//  CyclePredictionService.swift

import Foundation

struct CyclePredictionService {

    static func predictedStartDate(from archives: [ArchivedDataBlock]) -> Date? {
        // Menopause blocks have no cycle to predict from, whatever the caller passed in.
        let archives = archives.filter { $0.effectiveMode != .menopause }
        guard !archives.isEmpty else { return nil }

        let lengths: [Int] = archives.compactMap { block -> Int? in
            let allDates = block.groupedEvents.flatMap { $0.events }.map { $0.date }
            guard let first = allDates.min(), let last = allDates.max() else { return nil }
            let days = Calendar.current.dateComponents([.day], from: first, to: last).day.map { $0 + 1 }
            return days
        }.filter { $0 > 0 }

        guard !lengths.isEmpty else { return nil }
        let avgLength = lengths.reduce(0, +) / lengths.count

        let sortedByDate = archives.sorted { $0.date < $1.date }
        guard let lastBlock = sortedByDate.last else { return nil }
        let lastCycleDates = lastBlock.groupedEvents
            .filter { $0.eventType == .menstrual }
            .flatMap { $0.events }
            .map { $0.date }
        guard let lastStart = lastCycleDates.min() else { return nil }

        return Calendar.current.date(byAdding: .day, value: avgLength, to: lastStart)
    }

    static func daysUntilPrediction(from archives: [ArchivedDataBlock]) -> Int? {
        guard let predicted = predictedStartDate(from: archives) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date().startOfDay, to: predicted.startOfDay).day
        return days
    }
}
