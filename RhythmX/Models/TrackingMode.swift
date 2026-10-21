//
//  TrackingMode.swift
//  RhythmX
//

import Foundation

/// Which kind of tracking an event or archived block belongs to.
/// Stored as an optional field so data written by 1.9.x (which has no mode) decodes unchanged.
enum TrackingMode: String, Codable, CaseIterable, Identifiable {
    case cycle
    case planning
    case menopause

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cycle:     return "Cycle"
        case .planning:  return "Planning"
        case .menopause: return "Menopause"
        }
    }
}
