//  TagCategory.swift
//  Compiled into the app and the widget extension (Quick Log builds "Category:Value" tags).

import Foundation

/// Raw values are the prefix of stored tag strings ("Planning:Intercourse"), so they must not change.
enum TagCategory: String, CaseIterable, Codable {
    case dietary        = "Dietary"
    case exercise       = "Exercise"
    case medication     = "Medication"
    case mood           = "Mood"
    case symptom        = "Symptom"
    case cervicalMucus  = "Cervical Mucus"
    case basalTemp      = "Basal Temp"
    case other          = "Other"
    case planning       = "Planning"
    case menopause      = "Menopause"
}
