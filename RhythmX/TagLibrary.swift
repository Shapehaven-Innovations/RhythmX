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
        ]
    ]
}
