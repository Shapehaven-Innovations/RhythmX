// RhythmX/Views/InsightsViewModel.swift
import SwiftUI

struct InsightsViewModel {
    let events: [Event]
    let archivedBlocks: [ArchivedDataBlock]
    let appSettings: AppSettings

    init(events: [Event], archivedBlocks: [ArchivedDataBlock], appSettings: AppSettings) {
        self.events = events
        self.archivedBlocks = archivedBlocks
        self.appSettings = appSettings
    }

    // MARK: - Data Types

    struct StackedTagBar: Identifiable {
        var id: String { "\(phaseName)-\(categoryName)" }
        let phaseName: String
        let categoryName: String
        let percentage: Double
    }

    struct DailyTagCount: Identifiable {
        var id: Int { cycleDay }
        let cycleDay: Int
        let count: Int
        let color: Color
        let phaseName: String
    }

    struct AverageDailyTag: Identifiable {
        var id: Int { cycleDay }
        let cycleDay: Int
        let average: Double
    }

    struct TagCount: Identifiable {
        let id = UUID()
        let tag: String
        let shortTag: String
        let count: Int
    }

    struct CategoryTotal: Identifiable {
        let id = UUID()
        let category: String
        let count: Int
        let color: Color
    }

    struct PhaseSpan: Identifiable {
        let id = UUID()
        let label: String
        let phaseNumber: Int
        let startDay: Int
        let endDay: Int
        let color: Color
    }

    struct MucusPoint: Identifiable {
        let id = UUID()
        let cycleDay: Int
        let level: Int
        let color: Color
    }

    // MARK: - Migrated computed properties

    var stackedTagData: [StackedTagBar] {
        var result: [StackedTagBar] = []
        for phase in Event.EventType.allCases {
            var catFreq: [String: Int] = [:]
            let archivedEvents = archivedBlocks.flatMap { block in
                block.groupedEvents.filter { $0.eventType == phase }.flatMap { $0.events }
            }
            let currentEvents = events.filter { $0.eventType == phase }
            for event in archivedEvents + currentEvents {
                event.tags.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .forEach { tag in
                        let parts = tag.split(separator: ":", maxSplits: 1)
                        let catName = parts.count == 2
                            ? String(parts[0]).trimmingCharacters(in: .whitespaces)
                            : "Other"
                        catFreq[catName, default: 0] += 1
                    }
            }
            let total = catFreq.values.reduce(0, +)
            guard total > 0 else { continue }
            let phaseName = "\(phase.phaseNumber) \(phase.rawValue.capitalized)"
            for (cat, count) in catFreq.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
                result.append(StackedTagBar(phaseName: phaseName, categoryName: cat,
                                            percentage: Double(count) / Double(total) * 100))
            }
        }
        return result
    }

    var dailyTagData: [DailyTagCount] {
        let sorted = events.sorted { $0.date < $1.date }
        guard let firstDate = sorted.first?.date else { return [] }
        return sorted.compactMap { event in
            let tagCount = event.tags.split(separator: ",")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            guard tagCount > 0 else { return nil }
            let day = Calendar.current.dateComponents([.day], from: firstDate, to: event.date).day.map { $0 + 1 } ?? 1
            return DailyTagCount(
                cycleDay: day,
                count: tagCount,
                color: appSettings.phaseColor(for: event.eventType),
                phaseName: "\(event.eventType.phaseNumber) \(event.eventType.rawValue.capitalized)"
            )
        }
    }

    var tagCategoryTotals: [CategoryTotal] {
        let colorMap = Self.categoryColors
        var freq: [String: Int] = [:]
        let allEvents = events + archivedBlocks.flatMap { $0.groupedEvents.flatMap { $0.events } }
        for event in allEvents {
            event.tags.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .forEach { tag in
                    let parts = tag.split(separator: ":", maxSplits: 1)
                    let cat = parts.count == 2 ? String(parts[0]).trimmingCharacters(in: .whitespaces) : "Other"
                    freq[cat, default: 0] += 1
                }
        }
        return freq.sorted { $0.value > $1.value }.map { CategoryTotal(category: $0.key, count: $0.value, color: colorMap[$0.key] ?? .gray) }
    }

    func topTagsForPhase(_ phase: Event.EventType) -> [TagCount] {
        var freq: [String: Int] = [:]
        let archivedEvents = archivedBlocks.flatMap { block in
            block.groupedEvents.filter { $0.eventType == phase }.flatMap { $0.events }
        }
        for event in archivedEvents + events.filter({ $0.eventType == phase }) {
            event.tags.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .forEach { freq[$0, default: 0] += 1 }
        }
        return freq.sorted { $0.value > $1.value }.prefix(5).map { entry in
            let parts = entry.key.split(separator: ":", maxSplits: 1)
            let short = parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : entry.key
            return TagCount(tag: entry.key, shortTag: short, count: entry.value)
        }
    }

    var phaseSpans: [PhaseSpan] {
        let sorted = events.sorted { $0.date < $1.date }
        guard let firstDate = sorted.first?.date else { return [] }
        let grouped = Dictionary(grouping: sorted) { $0.eventType }
        return Event.EventType.allCases.compactMap { phase in
            guard let phaseEvents = grouped[phase], !phaseEvents.isEmpty else { return nil }
            let dates = phaseEvents.map { $0.date }.sorted()
            guard let first = dates.first, let last = dates.last else { return nil }
            let startDay = Calendar.current.dateComponents([.day], from: firstDate, to: first).day.map { $0 + 1 } ?? 1
            let endDay   = Calendar.current.dateComponents([.day], from: firstDate, to: last).day.map { $0 + 1 } ?? startDay
            return PhaseSpan(label: phaseLabel(phase), phaseNumber: phase.phaseNumber,
                             startDay: startDay, endDay: endDay + 1,
                             color: appSettings.phaseColor(for: phase))
        }
    }

    var cervicalMucusData: [MucusPoint] {
        let sorted = events.sorted { $0.date < $1.date }
        guard let firstDate = sorted.first?.date else { return [] }
        var points: [MucusPoint] = []
        for event in sorted {
            let day = Calendar.current.dateComponents([.day], from: firstDate, to: event.date).day.map { $0 + 1 } ?? 1
            for tag in event.tags.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                let lower = tag.lowercased()
                if lower.contains("cervical mucus:") || lower.hasPrefix("cervical mucus") {
                    let value = tag.split(separator: ":").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                    let level = mucusLevel(value)
                    if level > 0 { points.append(MucusPoint(cycleDay: day, level: level, color: mucusColor(level))) }
                }
            }
        }
        return points
    }

    var archivedCervicalMucusAverageData: [MucusPoint] {
        var buckets: [Int: [Int]] = [:]
        for archiveBlock in archivedBlocks {
            let blockEvents = archiveBlock.groupedEvents
                .flatMap { $0.events }
                .sorted { $0.date < $1.date }
            guard let anchor = blockEvents.first?.date else { continue }
            for event in blockEvents {
                let day = Calendar.current.dateComponents([.day], from: anchor, to: event.date).day.map { $0 + 1 } ?? 1
                for tag in event.tags.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                    let lower = tag.lowercased()
                    if lower.contains("cervical mucus:") || lower.hasPrefix("cervical mucus") {
                        let value = tag.split(separator: ":").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                        let level = mucusLevel(value)
                        if level > 0 { buckets[day, default: []].append(level) }
                    }
                }
            }
        }
        return buckets.sorted { $0.key < $1.key }.map { (day, levels) in
            let avg = Int((Double(levels.reduce(0, +)) / Double(levels.count)).rounded())
            return MucusPoint(cycleDay: day, level: avg, color: mucusColor(avg).opacity(0.3))
        }
    }

    /// One color per tag category; shared by the legend and the category totals.
    static let categoryColors: [String: Color] = [
        "Symptom": DS.Color.phase1Default, "Mood": DS.Color.phase4Default,
        "Dietary": DS.Color.phase3Default, "Exercise": DS.Color.phase2Default,
        "Medication": DS.Color.waveMid, "Cervical Mucus": DS.Color.waveBack,
        "Basal Temp": DS.Color.moon,
        "Other": DS.Color.secondaryText.opacity(0.4),
        "Planning": DS.Color.phase3Default.opacity(0.7),
        "Menopause": DS.Color.phase1Default.opacity(0.7)
    ]

    /// The menstrual categories the legend always lists.
    static let cycleCategoryNames = ["Symptom", "Mood", "Dietary", "Exercise", "Medication", "Cervical Mucus", "Basal Temp", "Other"]
    /// Every category, in legend order; also the chart's color scale domain.
    static let categoryNames = cycleCategoryNames + ["Planning", "Menopause"]

    /// The menstrual categories always; Planning and Menopause only once a tag of theirs is in the data,
    /// so Cycle-mode Insights look as they did before the modes existed.
    var categoryLegendItems: [(name: String, color: Color)] {
        let present = Set(stackedTagData.map(\.categoryName))
        return Self.categoryNames
            .filter { Self.cycleCategoryNames.contains($0) || present.contains($0) }
            .map { ($0, Self.categoryColors[$0] ?? .gray) }
    }

    func mucusLevel(_ value: String) -> Int {
        switch value.lowercased() {
        case "dry": return 1; case "sticky": return 2
        case "creamy": return 3; case "egg white": return 4
        default: return 0
        }
    }

    func mucusColor(_ level: Int) -> Color {
        switch level {
        case 1: return Color.gray.opacity(0.5)
        case 2: return DS.Color.phase3.opacity(0.6)
        case 3: return DS.Color.phase3
        case 4: return DS.Color.phase2
        default: return .clear
        }
    }

    func mucusLevelLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Dry"; case 2: return "Sticky"
        case 3: return "Creamy"; case 4: return "Egg White"
        default: return ""
        }
    }

    // MARK: - Private helpers

    private func phaseLabel(_ phase: Event.EventType) -> String {
        switch phase {
        case .menstrual:  return "Menstrual"
        case .follicular: return "Follicular"
        case .ovulation:  return "Fertile Window"
        case .luteal:     return "Luteal"
        }
    }

    // MARK: - New computed properties (implemented in Tasks 3 & 4)

    var tagsOverMonthAverageLine: [AverageDailyTag] {
        var buckets: [Int: [Int]] = [:]
        for archiveBlock in archivedBlocks {
            let blockEvents = archiveBlock.groupedEvents
                .flatMap { $0.events }
                .sorted { $0.date < $1.date }
            guard let anchor = blockEvents.first?.date else { continue }
            for event in blockEvents {
                let tagCount = event.tags.split(separator: ",")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                guard tagCount > 0 else { continue }
                let day = Calendar.current.dateComponents([.day], from: anchor, to: event.date)
                    .day.map { $0 + 1 } ?? 1
                buckets[day, default: []].append(tagCount)
            }
        }
        return buckets.sorted { $0.key < $1.key }.map { (day, counts) in
            AverageDailyTag(
                cycleDay: day,
                average: Double(counts.reduce(0, +)) / Double(counts.count)
            )
        }
    }
    var phaseSpansArchiveAverage: [PhaseSpan] {
        var startDaysByPhase: [Event.EventType: [Int]] = [:]
        var endDaysByPhase:   [Event.EventType: [Int]] = [:]

        for archiveBlock in archivedBlocks {
            let blockEvents = archiveBlock.groupedEvents
                .flatMap { $0.events }
                .sorted { $0.date < $1.date }
            guard let anchor = blockEvents.first?.date else { continue }
            let grouped = Dictionary(grouping: blockEvents) { $0.eventType }
            for phase in Event.EventType.allCases {
                guard let phaseEvents = grouped[phase], !phaseEvents.isEmpty else { continue }
                let dates = phaseEvents.map { $0.date }.sorted()
                guard let first = dates.first, let last = dates.last else { continue }
                let start = Calendar.current.dateComponents([.day], from: anchor, to: first).day.map { $0 + 1 } ?? 1
                let end   = Calendar.current.dateComponents([.day], from: anchor, to: last).day.map { $0 + 1 } ?? start
                startDaysByPhase[phase, default: []].append(start)
                endDaysByPhase[phase, default: []].append(end)
            }
        }

        return Event.EventType.allCases.compactMap { phase in
            guard let starts = startDaysByPhase[phase], !starts.isEmpty,
                  let ends   = endDaysByPhase[phase],   !ends.isEmpty else { return nil }
            let avgStart = starts.reduce(0, +) / starts.count
            let avgEnd   = ends.reduce(0, +) / ends.count
            return PhaseSpan(label: phaseLabel(phase), phaseNumber: phase.phaseNumber,
                             startDay: avgStart, endDay: avgEnd + 1, color: .gray)
        }
    }
}
