//  DailyInsightsService.swift
//  Produces the daily insights for today: builds `InsightFacts` from the stores, asks the writer, and caches
//  the result in UserDefaults per (date, mode, OS version, model availability). The cached day is reused only
//  while its facts are unchanged, so logging a tag or a new period writes a fresh day. The writer and the
//  clock are injected so tests run without the system model or the real date.

import Foundation

final class DailyInsightsService {
    static let storageKey = "dailyInsightsCache"

    private struct Entry: Codable {
        let key: String
        let facts: InsightFacts
        let insights: DailyInsights
    }

    private let writer: InsightWriting
    private let defaults: UserDefaults
    private let now: () -> Date
    private let osVersion: String
    private let calendar: Calendar
    /// `storageKey` for Today; the Daily insights notifier keeps its notes under its own key.
    private let storageKey: String

    init(writer: InsightWriting = FoundationModelsInsightWriter(),
         defaults: UserDefaults = AppGroup.defaults,
         now: @escaping () -> Date = Date.init,
         osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
         storageKey: String = DailyInsightsService.storageKey,
         calendar: Calendar = .current) {
        self.writer = writer
        self.defaults = defaults
        self.now = now
        self.osVersion = osVersion
        self.storageKey = storageKey
        self.calendar = calendar
    }

    /// "2026-10-20|cycle|26.5|ai": the day, the mode, the OS version and whether the model was available.
    func cacheKey(for facts: InsightFacts) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now())
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return [day, facts.mode.rawValue, osVersion, writer.isModelAvailable ? "ai" : "template"].joined(separator: "|")
    }

    /// The insights for these facts today: the cached day when its key and facts match, else a fresh one.
    func insights(for facts: InsightFacts) async -> DailyInsights {
        if let cached = cachedInsights(for: facts) { return cached }
        let insights = await writer.insights(for: facts)
        if let data = try? JSONEncoder().encode(Entry(key: cacheKey(for: facts), facts: facts, insights: insights)) {
            defaults.set(data, forKey: storageKey)
        }
        return insights
    }

    /// The cached day for these facts today, without writing anything; nil when the key or the facts differ.
    func cachedInsights(for facts: InsightFacts) -> DailyInsights? {
        guard let cached = cachedEntry(), cached.key == cacheKey(for: facts), cached.facts == facts else { return nil }
        return cached.insights
    }

    /// Builds today's facts (by the injected clock) from the stores' events, then `insights(for:)`.
    func insights(events: [Event], archivedBlocks: [ArchivedDataBlock], mode: TrackingMode,
                  fertileOverrides: FertileOverrides = FertileOverrides(),
                  sleepSummary: [Date: TimeInterval] = [:]) async -> DailyInsights {
        let facts = InsightFacts.make(events: events, archivedBlocks: archivedBlocks, mode: mode, today: now(),
                                      fertileOverrides: fertileOverrides, sleepSummary: sleepSummary, calendar: calendar)
        return await insights(for: facts)
    }

    /// Forgets the cached day (for example after Replace from a backup or erasing data).
    func clearCache() {
        defaults.removeObject(forKey: storageKey)
    }

    private func cachedEntry() -> Entry? {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
    }
}
