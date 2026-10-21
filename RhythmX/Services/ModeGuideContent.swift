//  ModeGuideContent.swift
//
//  "Learn about phases" content for Planning and Menopause: short plain topics, each pointing at the library
//  tags to log for it. Cycle mode has no extra guide; it keeps the four phase entries in PhaseGuideContent.

import Foundation

struct ModeGuideTag: Equatable, Hashable {
    let category: TagCategory
    let value: String
    var raw: String { "\(category.rawValue):\(value)" }
}

struct ModeGuideTopic: Equatable, Identifiable {
    let title: String
    let symbolName: String
    let text: String
    let tags: [ModeGuideTag]
    var id: String { title }
}

struct ModeGuide: Equatable {
    let mode: TrackingMode
    let title: String
    let intro: String
    let topics: [ModeGuideTopic]
    let disclaimer: String

    var modeLabel: String { "\(mode.title) mode" }
}

enum ModeGuideContent {
    static let disclaimer = "Tracking tool, not medical advice."

    /// Shown on the Planning category of the Add Tag page and in the Planning guide.
    static let ovulationTestExplanation =
        "Ovulation tests are at-home test strips that detect the hormone surge that comes a day or two before ovulation. Log the result you see: Negative, Faint, Positive or Peak."

    /// Nil for Cycle mode, which keeps the phase entries exactly as they are.
    static func guide(for mode: TrackingMode) -> ModeGuide? {
        switch mode {
        case .cycle:     return nil
        case .planning:  return planning
        case .menopause: return menopause
        }
    }

    private static func tags(_ category: TagCategory, _ values: [String]) -> [ModeGuideTag] {
        values.map { ModeGuideTag(category: category, value: $0) }
    }

    static let planning = ModeGuide(
        mode: .planning,
        title: "Trying to conceive",
        intro: "These signs help you see your fertile days. Log what you notice and RhythmX lines it up with your cycle.",
        topics: [
            ModeGuideTopic(
                title: "Fertile window",
                symbolName: "calendar",
                text: "The fertile window is the few days before ovulation and the day itself. The Calendar marks it from your cycle. Predictions are estimates and are not birth control.",
                tags: tags(.cervicalMucus, ["Egg White"])),
            ModeGuideTopic(
                title: "Ovulation tests",
                symbolName: "testtube.2",
                text: ovulationTestExplanation,
                tags: tags(.planning, ["Ovulation Test Negative", "Ovulation Test Faint",
                                       "Ovulation Test Positive", "Ovulation Test Peak"])),
            ModeGuideTopic(
                title: "Basal temperature",
                symbolName: "thermometer.medium",
                text: "Take your temperature first thing in the morning, before you get up. A rise that stays up for three days suggests ovulation has passed. Log the reading under Basal Temp, or tag Elevated BBT.",
                tags: tags(.basalTemp, ["Elevated BBT"])),
            ModeGuideTopic(
                title: "Cervical mucus",
                symbolName: "drop",
                text: "Mucus often turns clear and stretchy, like egg white, in the days before ovulation. Log what you see each day.",
                tags: tags(.cervicalMucus, ["Dry", "Sticky", "Creamy", "Egg White"])),
            ModeGuideTopic(
                title: "Intercourse timing",
                symbolName: "heart",
                text: "Log intercourse to see how it lines up with your fertile window. The days just before ovulation count the most when trying to conceive.",
                tags: tags(.planning, ["Intercourse", "Fertility Supplement"])),
        ],
        disclaimer: disclaimer)

    static let menopause = ModeGuide(
        mode: .menopause,
        title: "Tracking menopause",
        intro: "Changes in perimenopause and menopause come and go. Logging them helps you spot patterns and bring a clear record to your doctor.",
        topics: [
            ModeGuideTopic(
                title: "Hot flashes and night sweats",
                symbolName: "flame",
                text: "Sudden waves of heat, by day or at night. Log each one; these two tags can be logged more than once a day.",
                tags: tags(.menopause, ["Hot Flashes", "Night Sweats"])),
            ModeGuideTopic(
                title: "Sleep",
                symbolName: "bed.double",
                text: "Sleep often changes. Tag poor nights to see whether they follow night sweats or busy days.",
                tags: tags(.menopause, ["Poor Sleep"])),
            ModeGuideTopic(
                title: "Mood and focus",
                symbolName: "brain.head.profile",
                text: "Mood shifts and brain fog are common. A quick tag on the day makes patterns easier to see later.",
                tags: tags(.menopause, ["Brain Fog"]) + tags(.mood, ["Irritable", "Anxious", "Mood Swings", "Low Energy"])),
            ModeGuideTopic(
                title: "Body changes",
                symbolName: "figure.stand",
                text: "Note other changes as they happen, such as joint pain, dryness, a lower libido or a racing heart.",
                tags: tags(.menopause, ["Joint Pain", "Vaginal Dryness", "Low Libido", "Heart Palpitations"])),
        ],
        disclaimer: disclaimer)
}
