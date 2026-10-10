//  TagParser.swift

import Foundation

struct TagChip: Identifiable, Equatable {
    let raw: String
    let label: String
    let count: Int
    var id: String { raw }
}

enum TagParser {
    /// "Category:Value, Category:Value" into trimmed, non-empty raw tags.
    static func split(_ tags: String) -> [String] {
        tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Display text: everything after the first colon, trimmed. No colon returns the raw tag.
    static func label(for raw: String) -> String {
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func chips(from tagStrings: [String]) -> [TagChip] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for s in tagStrings {
            for raw in split(s) {
                if counts[raw] == nil { order.append(raw) }
                counts[raw, default: 0] += 1
            }
        }
        return order
            .map { TagChip(raw: $0, label: label(for: $0), count: counts[$0] ?? 0) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    static func removing(_ raw: String, from tags: String) -> String {
        split(tags).filter { $0 != raw }.joined(separator: ", ")
    }
}
