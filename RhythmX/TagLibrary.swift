//  TagLibrary.swift

import Foundation

enum TagLibrary {
    static let tags: [TagCategory: [String]] = [
        .symptom: [
            "Cramps", "Bloating", "Headache", "Fatigue", "Back Pain",
            "Nausea", "Breast Tenderness", "Pelvic Pain", "Spotting"
        ],
        .mood: [
            "Irritable", "Anxious", "Happy", "Low Energy", "Focused",
            "Mood Swings", "Calm", "Emotional", "Motivated"
        ],
        .dietary: [
            "Chocolate Craving", "Salty Craving", "Increased Appetite",
            "Decreased Appetite", "Bloating After Eating", "Sweet Craving"
        ],
        .exercise: [
            "Light Walk", "Yoga", "High Intensity", "Rest Day",
            "Stretching", "Swimming", "Cycling"
        ],
        .medication: [
            "Ibuprofen", "Naproxen", "Birth Control", "Iron Supplement",
            "Magnesium", "Vitamin D", "Acetaminophen"
        ],
        .cervicalMucus: [
            "Dry", "Sticky", "Creamy", "Egg White"
        ],
        .basalTemp: [
            "Elevated BBT"
        ],
        .other: [
            "Poor Sleep", "Acne", "Water Retention", "Hot Flashes",
            "Night Sweats", "Mild Cramping"
        ],
        .planning: [
            "Ovulation Test Negative", "Ovulation Test Faint", "Ovulation Test Positive",
            "Ovulation Test Peak", "Intercourse", "Fertility Supplement"
        ],
        .menopause: [
            "Hot Flashes", "Night Sweats", "Poor Sleep", "Brain Fog", "Joint Pain",
            "Vaginal Dryness", "Low Libido", "Heart Palpitations"
        ]
    ]

    /// Categories in the order the tag form shows them for a mode. The mode's own category comes first;
    /// the rest of `TagCategory.allCases` stays reachable under "More".
    static func categories(for mode: TrackingMode) -> [TagCategory] {
        switch mode {
        case .cycle:     return [.symptom, .mood, .dietary, .exercise, .medication, .cervicalMucus, .basalTemp, .other]
        case .planning:  return [.planning, .cervicalMucus, .basalTemp, .mood, .symptom, .medication, .other]
        case .menopause: return [.menopause, .mood, .symptom, .medication, .other]
        }
    }

    /// Tags that may be logged more than once on the same day. Every other tag is one per day.
    private static let repeatable: Set<String> = ["Menopause:Hot Flashes", "Menopause:Night Sweats"]

    static func isRepeatable(_ category: TagCategory, _ value: String) -> Bool {
        repeatable.contains("\(category.rawValue):\(value.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    /// Same check for a stored "Category:Value" string.
    static func isRepeatable(raw: String) -> Bool {
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let category = TagCategory(rawValue: parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return isRepeatable(category, String(parts[1]))
    }
}
