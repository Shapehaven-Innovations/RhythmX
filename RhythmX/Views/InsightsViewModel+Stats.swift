// RhythmX/Views/InsightsViewModel+Stats.swift
import Foundation

extension InsightsViewModel {

    struct CycleStats: Equatable {
        var averageCycleLength: Int?
        var averagePeriodLength: Int?
        var currentCycleDay: Int?
        var currentPhase: Event.EventType?
        var nextPeriodEstimate: Date?
    }

    func cycleStats(today: Date = Date()) -> CycleStats {
        let currentDates = events.map(\.date)
        let currentStart = currentDates.min()?.startOfDay
        let currentSpan = Self.spanDays(currentDates)

        // Cycle length: archived cycles when present, else the current one.
        let archivedSpans = archivedBlocks.compactMap {
            Self.spanDays($0.groupedEvents.flatMap { $0.events }.map(\.date))
        }
        let cycleLengths = archivedSpans.isEmpty ? (currentSpan.map { [$0] } ?? []) : archivedSpans

        // Period length: count of menstrual days.
        let archivedPeriods = archivedBlocks.compactMap { block -> Int? in
            let n = block.groupedEvents.filter { $0.eventType == .menstrual }.reduce(0) { $0 + $1.events.count }
            return n > 0 ? n : nil
        }
        let currentPeriod = events.filter { $0.eventType == .menstrual }.count
        let periodLengths = archivedPeriods.isEmpty ? (currentPeriod > 0 ? [currentPeriod] : []) : archivedPeriods

        var day: Int?
        var phase: Event.EventType?
        if let start = currentStart, let span = currentSpan {
            let offset = Calendar.current.dateComponents([.day], from: start, to: today.startOfDay).day ?? -1
            if offset >= 0 && offset < span {
                day = offset + 1
                phase = events.first { $0.date.startOfDay == today.startOfDay }?.eventType
            }
        }

        let next: Date?
        if let start = currentStart, let span = currentSpan {
            next = Calendar.current.date(byAdding: .day, value: span, to: start)
        } else {
            next = CyclePredictionService.predictedStartDate(from: archivedBlocks)
        }

        return CycleStats(
            averageCycleLength: Self.average(cycleLengths),
            averagePeriodLength: Self.average(periodLengths),
            currentCycleDay: day,
            currentPhase: phase,
            nextPeriodEstimate: next
        )
    }

    private static func spanDays(_ dates: [Date]) -> Int? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let d = Calendar.current.dateComponents([.day], from: first.startOfDay, to: last.startOfDay).day ?? 0
        return d + 1
    }

    private static func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
