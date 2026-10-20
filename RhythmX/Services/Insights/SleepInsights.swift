//  SleepInsights.swift
//  Pure numbers behind the Sleep card in Menopause Insights: the last 7 nights from the summary HealthSync
//  imported from Apple Health (`HealthSync.importedSleep`), their average and the hours text. Sleep is never
//  copied into events.

import Foundation

struct SleepInsights: Equatable {
    struct Night: Equatable, Identifiable {
        /// Start of the day the night ended on (the morning after), the summary's key.
        let date: Date
        /// Hours asleep; nil when Health has no sleep for that night.
        let hours: Double?
        var id: Date { date }
    }

    static let nightCount = 7

    /// The last 7 nights, oldest first; the last one ended this morning.
    let nights: [Night]

    var nightsWithSleep: Int { nights.filter { $0.hours != nil }.count }
    var hasData: Bool { nightsWithSleep > 0 }

    /// Average hours over the nights that have sleep; nil without any.
    var averageHours: Double? {
        let values = nights.compactMap(\.hours)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func make(summary: [Date: TimeInterval], today: Date, calendar: Calendar = .current) -> SleepInsights {
        let today = calendar.startOfDay(for: today)
        let nights = (0..<nightCount).reversed().compactMap { back -> Night? in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let seconds = summary[day] ?? 0
            return Night(date: day, hours: seconds > 0 ? seconds / 3600 : nil)
        }
        return SleepInsights(nights: nights)
    }

    // MARK: - Text

    /// Hours rounded to one decimal, without a trailing ".0".
    static func rounded(_ hours: Double) -> String {
        let value = (hours * 10).rounded() / 10
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// "7.3 h", for the chart and the average.
    static func hoursText(_ hours: Double) -> String { "\(rounded(hours)) h" }

    /// "7.3 hours", for VoiceOver.
    static func spokenHours(_ hours: Double) -> String {
        let text = rounded(hours)
        return text == "1" ? "1 hour" : "\(text) hours"
    }

    var accessibilitySummary: String {
        guard let average = averageHours else { return "No sleep from Apple Health in the last 7 nights." }
        var text = "Average \(Self.spokenHours(average)) asleep over \(nightsWithSleep) of the last \(Self.nightCount) nights."
        if let last = nights.last?.hours { text += " Last night \(Self.spokenHours(last))." }
        return text
    }

    /// The empty state: where the sleep comes from and, while reading is off, how to turn it on.
    static func emptyMessage(readSleepOn: Bool) -> String {
        readSleepOn
            ? "No sleep from Apple Health in the last 7 nights. Health records sleep with iPhone Sleep Focus or an Apple Watch."
            : "This card reads Sleep from Apple Health, recorded with iPhone Sleep Focus or an Apple Watch. To show it, turn on Read sleep in Settings under Apple Health."
    }
}
