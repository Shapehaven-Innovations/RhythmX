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

    /// How strong each tag was, keyed by the exact stored "Category:Value" string, 1 to 3 (`TagIntensity`).
    /// Nil for tags logged without a level and for all data written before the intensity rows. Omitted from
    /// JSON when nil or empty, so a store or backup without intensities keeps the 1.9.x shape.
    var tagIntensity: [String: Int]?

    /// The stored keys. Same names as the synthesized ones; declared because both coding methods are custom.
    enum CodingKeys: String, CodingKey {
        case id, eventType, date, note, tags, mode, tagIntensity
    }

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
        mode: TrackingMode? = nil,
        tagIntensity: [String: Int]? = nil
    ) {
        self.id = id
        self.eventType = eventType
        self.date = date
        self.note = note
        self.tags = tags
        self.mode = mode
        self.tagIntensity = Self.sanitized(tagIntensity)
    }
}

extension Event {
    /// Same keys as the synthesized decoder, except an unknown `mode` (written by a newer version)
    /// decodes as nil instead of failing the whole array, and an unreadable `tagIntensity` decodes as nil
    /// with levels outside 1 to 3 dropped.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        eventType = try container.decode(EventType.self, forKey: .eventType)
        date = try container.decode(Date.self, forKey: .date)
        note = try container.decode(String.self, forKey: .note)
        tags = try container.decode(String.self, forKey: .tags)
        mode = (try? container.decodeIfPresent(TrackingMode.self, forKey: .mode)) ?? nil
        tagIntensity = Self.sanitized((try? container.decodeIfPresent([String: Int].self, forKey: .tagIntensity)) ?? nil)
    }

    /// The synthesized keys and order. `mode` is left out when nil and `tagIntensity` when nil or empty,
    /// exactly as before intensities existed.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(eventType, forKey: .eventType)
        try container.encode(date, forKey: .date)
        try container.encode(note, forKey: .note)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(mode, forKey: .mode)
        if let tagIntensity, !tagIntensity.isEmpty {
            try container.encode(tagIntensity, forKey: .tagIntensity)
        }
    }
}

// MARK: - Tag intensity

/// How strong a logged tag was. Stored as its raw value in `Event.tagIntensity`.
enum TagIntensity: Int, CaseIterable, Codable, Identifiable, Comparable {
    case light = 1
    case medium = 2
    case heavy = 3

    var id: Int { rawValue }

    static func < (lhs: TagIntensity, rhs: TagIntensity) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .light:  return "Light"
        case .medium: return "Medium"
        case .heavy:  return "Heavy"
        }
    }
}

extension Event {
    /// The level stored for `raw`, or nil when it was logged without one.
    func intensity(for raw: String) -> TagIntensity? {
        tagIntensity?[raw].flatMap(TagIntensity.init(rawValue:))
    }

    /// Sets or (with nil) removes the level for `raw`. An emptied map becomes nil so it is not encoded.
    mutating func setIntensity(_ level: TagIntensity?, for raw: String) {
        var map = tagIntensity ?? [:]
        map[raw] = level?.rawValue
        tagIntensity = map.isEmpty ? nil : map
    }

    /// Drops levels whose tag is no longer in `tags` (after an edit or a removal).
    mutating func pruneIntensities() {
        guard let map = tagIntensity else { return }
        let present = Set(TagParser.split(tags))
        let kept = map.filter { present.contains($0.key) }
        tagIntensity = kept.isEmpty ? nil : kept
    }

    /// Both maps together, keeping the higher level for a tag in both. Nil when neither has a level.
    static func mergedIntensity(_ a: [String: Int]?, _ b: [String: Int]?) -> [String: Int]? {
        let merged = (a ?? [:]).merging(b ?? [:]) { max($0, $1) }
        return sanitized(merged)
    }

    /// Only levels 1 to 3; nil when nothing is left.
    static func sanitized(_ map: [String: Int]?) -> [String: Int]? {
        guard let map else { return nil }
        let valid = map.filter { TagIntensity(rawValue: $0.value) != nil }
        return valid.isEmpty ? nil : valid
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
