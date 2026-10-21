//
//  ArchivedDataBlock.swift
//

import Foundation

struct ArchivedDataBlock: Codable, Identifiable {
    let id: UUID
    let date: Date
    let groupedEvents: [PhaseEvents]

    /// Tracking mode this block was archived under. Nil for data written before 2.0.
    let mode: TrackingMode?

    /// Custom initializer that allows you to
    /// specify an existing id, or generate a new one.
    init(id: UUID = UUID(), date: Date, groupedEvents: [PhaseEvents], mode: TrackingMode? = nil) {
        self.id = id
        self.date = date
        self.groupedEvents = groupedEvents
        self.mode = mode
    }

    /// The mode to treat this block as. Legacy blocks with no stored mode are cycle blocks.
    var effectiveMode: TrackingMode { mode ?? .cycle }

    /// Same keys as the synthesized decoder, except an unknown `mode` (written by a newer version)
    /// decodes as nil instead of failing the whole array. Encoding stays synthesized.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        groupedEvents = try container.decode([PhaseEvents].self, forKey: .groupedEvents)
        mode = (try? container.decodeIfPresent(TrackingMode.self, forKey: .mode)) ?? nil
    }

    struct PhaseEvents: Codable {
        let eventType: Event.EventType
        let events: [Event]
    }
}
