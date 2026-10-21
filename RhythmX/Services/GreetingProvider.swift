//  GreetingProvider.swift
//  The greeting at the top of Today. Pure, and compiled into the app and the widget extension (AppSettings.swift,
//  which both compile, stores the style). Only three greetings ever appear: "Good morning", "Good afternoon" and
//  "Good evening", with ", <name>" added when the person chose to be greeted by name.

import Foundation

/// How Today greets the person. Stored as its raw value under `AppSettings.greetingStyleKey`.
enum GreetingStyle: String, CaseIterable, Identifiable {
    /// "Good morning" and so on. The default.
    case greeting
    /// The greeting followed by the name the person typed.
    case name
    /// No greeting at all.
    case off

    var id: String { rawValue }

    /// The stored value, or the default for anything unknown.
    init(stored: String) {
        self = GreetingStyle(rawValue: stored) ?? .greeting
    }
}

enum GreetingProvider {
    /// "Good morning" from 5:00 to 11:59, "Good afternoon" from 12:00 to 16:59, "Good evening" from 17:00 to
    /// 4:59. With `.name` and a non-blank name, ", <name>" follows. Nil when the greeting is off.
    static func text(now: Date, style: GreetingStyle, name: String, calendar: Calendar = .current) -> String? {
        guard style != .off else { return nil }
        let hour = calendar.component(.hour, from: now)
        let greeting: String
        switch hour {
        case 5..<12:  greeting = "Good morning"
        case 12..<17: greeting = "Good afternoon"
        default:      greeting = "Good evening"
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard style == .name, !trimmed.isEmpty else { return greeting }
        return "\(greeting), \(trimmed)"
    }
}
