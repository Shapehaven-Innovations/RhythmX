//  InfoCopy.swift
//  Every explanation behind an info circle (`InfoButton`), in one place so it is tested. Cards show a
//  one-line summary; the longer text lives here. Plain sentences, no dashes as asides, no emoji.
//  Never behind a circle (always on the page): "Predictions are estimates and are not birth control.",
//  "Tracking tool, not medical advice.", the paywall's trial and renewal terms with its links, and any error
//  or denied state.

import Foundation

struct InfoTopic: Identifiable, Equatable {
    let id: String
    let title: String
    let paragraphs: [String]
    /// A quieter last line, for example "Tracking tool, not medical advice.".
    var footnote: String? = nil

    /// What VoiceOver says for the circle.
    var accessibilityLabel: String { "About \(title)" }
}

enum InfoCopy {
    /// Lines that stay visible wherever they apply and are never moved into a topic.
    static let alwaysVisible = [PlanningInsightsView.disclaimer, MenopauseInsightsView.disclaimer]

    // MARK: - Notifications

    static let periodReminders = InfoTopic(
        id: "notifications.period", title: "Period reminders",
        paragraphs: [
            "A reminder at 8:00 AM the day before and on the day your next period is expected. Pick either one or both.",
            "The day is estimated from your past cycles, so it can move as you log.",
        ])

    static let fertileReminders = InfoTopic(
        id: "notifications.fertile", title: "Fertile window",
        paragraphs: [
            "A reminder at 8:00 AM on the first day of your estimated fertile window, and one on your likely ovulation day.",
            "Both days are estimated from your cycles and any ovulation tests you log. They are not scheduled in Menopause mode.",
        ])

    static let dailyInsights = InfoTopic(
        id: "notifications.dailyInsights", title: "Daily insights",
        paragraphs: [
            "One short note a day about your phase and your own patterns, with a reminder to log a tag.",
            "It is written on this iPhone a few hours before the time you pick, when RhythmX is opened or gets background time. That needs Background App Refresh on for RhythmX in iOS Settings.",
            "If that does not happen in time, you get a standard note for your phase instead.",
            "Tapping the note opens a one-step log. Nothing leaves this device.",
        ],
        footnote: MenopauseInsightsView.disclaimer)

    static let discreetLockScreen = InfoTopic(
        id: "notifications.discreet", title: "Lock Screen privacy",
        paragraphs: [
            "With this on, every RhythmX notification hides its details: period reminders, fertile window reminders, the weekly review and Daily insights.",
            "Reminders only say \"\(NotificationScheduler.discreetReminderBody)\" and the Daily insights note only says \"\(NotificationScheduler.discreetInsightBody)\", with no cycle details.",
            "Inside RhythmX nothing changes. Useful if you share a phone or leave it on a desk.",
        ])

    static let weeklyReview = InfoTopic(
        id: "notifications.weekly", title: "Weekly review",
        paragraphs: [
            "One reminder a week, on the day and at the time you pick, to look at your patterns from the week.",
            "Tapping it opens Patterns on the Tags tab.",
        ])

    // MARK: - Settings

    static let appleHealth = InfoTopic(
        id: "settings.health", title: "Apple Health",
        paragraphs: [
            "Period days are written to Health as menstrual flow, once per day. If you remove a period day here, the entry RhythmX wrote is removed from Health too.",
            "Turning off Write period days stops new writes and keeps what is already in Health.",
            "Temperature and sleep from Health show on Today and are offered in the tag form; they are not added to your events.",
            "Each switch asks Health for its own permission. Nothing leaves this device.",
        ])

    static let appleCalendar = InfoTopic(
        id: "settings.calendar", title: "Apple Calendar",
        paragraphs: [
            "One way, into a calendar named RhythmX kept On My iPhone, so it stays on this device. Turning this off removes every event RhythmX added.",
            "If your calendars are stored only in iCloud and this iPhone has no On My iPhone calendars, the RhythmX calendar is made in iCloud and syncs through your iCloud account. The Calendar card says so when that happens.",
            "RhythmX asks for full calendar access because Apple Calendar only lets an app create its own calendar and update or remove its events at that level. RhythmX reads and writes only the RhythmX calendar.",
            "Discreet titles use short symbols, for a calendar you share with someone else.",
        ])

    static let backup = InfoTopic(
        id: "settings.backup", title: "Backup and restore",
        paragraphs: [
            "A backup is one RhythmX file with your cycles, entries, tags and settings. You can protect it with a passphrase.",
            "You choose where it goes, for example Files or iCloud Drive. RhythmX never uploads it.",
            "Restore opens a RhythmX file from Files, AirDrop or Mail. Before a Replace restore, a copy of your current data is kept on this phone for 30 days.",
        ])

    static let plus = InfoTopic(
        id: "settings.plus", title: "RhythmX Plus",
        paragraphs: [
            "Plus adds unlimited PDFs, the Blue Moon, Harvest Moon and Eclipse themes, the Week Strip and Quick Log widgets and Apple Calendar sync.",
            "Tracking, insights, all notifications, Apple Health, backup, the phase widget and the Blush theme stay free.",
            "Without Plus, a Day Pass unlocks both PDFs until the start of the next day.",
        ])

    static let greeting = InfoTopic(
        id: "settings.greeting", title: "Greeting",
        paragraphs: [
            "Today can greet you by the time of day, with your name, or not at all.",
            "Your name stays on this iPhone. It is shown on Today only.",
        ])

    // MARK: - Cycles

    static let newCycle = InfoTopic(
        id: "cycles.newCycle", title: "Start a new cycle",
        paragraphs: [
            "Pick the first day of your period and your usual cycle length. RhythmX fills in the four phases from that day.",
            "If you already have events, you'll be asked whether to archive them first. Archived cycles move to Past cycles.",
        ])

    static let freshStretch = InfoTopic(
        id: "cycles.freshStretch", title: "Start a fresh stretch",
        paragraphs: [
            "Pick a first day and a length to start over from that day. Your Menopause entries stay.",
            "If you already have entries, you'll be asked whether to archive the older ones first. The last week stays.",
        ])

    // MARK: - Share and Export

    static let share = InfoTopic(
        id: "share", title: "Sharing cards",
        paragraphs: [
            "Cards are made on this iPhone and handed to the iOS share sheet. Nothing is uploaded, and there is no account or live sync.",
            "Only the cards you pick leave your iPhone, as images. Tags, notes and dates are never included.",
            "Add to calendar makes a calendar file (.ics) with your phase days, for someone who wants them in their own calendar.",
        ])

    static let exportPrivacy = InfoTopic(
        id: "export.privacy", title: "Your details on the report",
        paragraphs: [
            ExportCopy.privacyNote,
            "The PDF is made on this iPhone. It leaves only when you share or save it.",
        ])

    static let all: [InfoTopic] = [
        periodReminders, fertileReminders, dailyInsights, discreetLockScreen, weeklyReview,
        appleHealth, appleCalendar, backup, plus, greeting, newCycle, freshStretch, share, exportPrivacy,
    ]
}
