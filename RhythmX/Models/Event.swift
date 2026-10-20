//
//  Event.swift
//  Created by user on 9/27/24.
//

import Foundation

struct Event: Identifiable, Codable {
    enum EventType: String, Identifiable, CaseIterable, Codable {
        case menstrual
        case follicular
        case ovulation
        case luteal

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .menstrual:     return "❶"
            case .follicular:    return "❷"
            case .ovulation:     return "❸"
            case .luteal:        return "❹"
            }
        }
    }

    /// Unique string ID for each event
    var id: String

    var eventType: EventType
    var date: Date

    /// Optional note describing the event
    var note: String

    /// Freeform text for custom tags
    var tags: String

    /// Tracking mode this event was logged under. Nil for data written before 2.0.
    var mode: TrackingMode?

    /// Computed property to convert the event's date to DateComponents
    var dateComponents: DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: date)
    }

    // MARK: - Initializer
    init(
        id: String = UUID().uuidString,
        eventType: EventType,
        date: Date,
        note: String,
        tags: String = "",
        mode: TrackingMode? = nil
    ) {
        self.id = id
        self.eventType = eventType
        self.date = date
        self.note = note
        self.tags = tags
        self.mode = mode
    }
}

extension Event {
    /// Same keys as the synthesized decoder, except an unknown `mode` (written by a newer version)
    /// decodes as nil instead of failing the whole array. Encoding stays synthesized.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        eventType = try container.decode(EventType.self, forKey: .eventType)
        date = try container.decode(Date.self, forKey: .date)
        note = try container.decode(String.self, forKey: .note)
        tags = try container.decode(String.self, forKey: .tags)
        mode = (try? container.decodeIfPresent(TrackingMode.self, forKey: .mode)) ?? nil
    }
}

extension Event {
    /// The mode to treat this event as. Legacy events with no stored mode are cycle events.
    var effectiveMode: TrackingMode { mode ?? .cycle }
}

// MARK: - Sample Events
extension Event {
    static var sampleEvents: [Event] {
        return [
            Event(eventType: .menstrual, date: Date(), note: "Menstrual phase", tags: ""),
            Event(eventType: .follicular, date: Date().addingTimeInterval(86400), note: "Follicular phase", tags: ""),
            Event(eventType: .ovulation, date: Date().addingTimeInterval(172800), note: "Ovulation phase", tags: ""),
            Event(eventType: .luteal, date: Date().addingTimeInterval(259200), note: "Luteal phase", tags: ""),
        ]
    }
}
