//  SkinTag.swift

import Foundation

struct SkinTag: Equatable, Hashable {
    enum Area: String, CaseIterable, Identifiable {
        case face = "Face", forehead = "Forehead", cheeks = "Cheeks", chin = "Chin", jaw = "Jaw", nose = "Nose"
        case neck = "Neck", chest = "Chest", back = "Back", shoulders = "Shoulders", arms = "Arms", other = "Other"
        var id: String { rawValue }
    }
    enum Kind: String, CaseIterable, Identifiable {
        case clear = "Clear", acne = "Acne", breakout = "Breakout", dry = "Dry", oily = "Oily", flaky = "Flaky", irritated = "Irritated"
        var id: String { rawValue }
    }
    enum Colour: String, CaseIterable, Identifiable {
        case red = "Red", pink = "Pink", darkSpots = "Dark spots", pale = "Pale"
        var id: String { rawValue }
    }

    static let prefix = "Skin:"
    static let legacyAcneRaw = "Other:Acne"

    let area: Area
    let kinds: [Kind]
    let colour: Colour?

    init?(area: Area, kinds: Set<Kind>, colour: Colour?) {
        guard !kinds.isEmpty else { return nil }
        self.area = area
        if kinds.contains(.clear) {
            self.kinds = [.clear]
            self.colour = nil
        } else {
            self.kinds = Kind.allCases.filter { kinds.contains($0) }
            self.colour = colour
        }
    }

    var value: String {
        var s = "\(area.rawValue)/\(kinds.map(\.rawValue).joined(separator: "+"))"
        if let colour { s += "/\(colour.rawValue)" }
        return s
    }

    var raw: String { Self.prefix + value }

    var displayLabel: String {
        var parts = [area.rawValue, kinds.map(\.rawValue).joined(separator: ", ")]
        if let colour { parts.append(colour.rawValue) }
        return parts.joined(separator: " · ")
    }

    var isFlare: Bool { kinds != [.clear] }

    static func parse(_ raw: String) -> SkinTag? {
        guard raw.hasPrefix(prefix) else { return nil }
        let parts = raw.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3, let area = Area(rawValue: parts[0]) else { return nil }
        var kinds = Set<Kind>()
        for k in parts[1].split(separator: "+", omittingEmptySubsequences: false) {
            guard let kind = Kind(rawValue: String(k)) else { return nil }
            kinds.insert(kind)
        }
        var colour: Colour?
        if parts.count == 3 {
            guard let c = Colour(rawValue: parts[2]) else { return nil }
            colour = c
        }
        guard let tag = SkinTag(area: area, kinds: kinds, colour: colour), tag.raw == raw else { return nil }
        return tag
    }

    static func fromLegacyAcne(_ raw: String) -> SkinTag? {
        raw == legacyAcneRaw ? SkinTag(area: .face, kinds: [.acne], colour: nil) : nil
    }

    static func parseAny(_ raw: String) -> SkinTag? { parse(raw) ?? fromLegacyAcne(raw) }

    static func isSkinRaw(_ raw: String) -> Bool { raw.hasPrefix(prefix) }
}
