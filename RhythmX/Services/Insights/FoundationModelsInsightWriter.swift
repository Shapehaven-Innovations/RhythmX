//  FoundationModelsInsightWriter.swift
//  The on-device writer. Where Apple Intelligence is available (`SystemLanguageModel.default.availability`),
//  Apple's Foundation Models framework rewords the mood line, the energy tile and the pattern tile from
//  `InsightFacts` only (counts and labels, never dates, notes or raw tag strings). The output is a
//  @Generable struct with a tight token budget (the context is 4,096 tokens shared by prompt and answer).
//  Every text then passes `InsightTextValidator`; on unavailability, an error (rate limit, refusal,
//  context overflow) or any failed check, the template writer's day is used unchanged.
//  Numbers and fertility lines (cycle day, fertile window) always stay with the template.

import Foundation
import FoundationModels

/// Produces the on-device texts. A protocol so tests can stand in for the system model.
protocol InsightTextGenerating {
    var isAvailable: Bool { get }
    func generate(for facts: InsightFacts) async throws -> GeneratedInsightText
}

struct FoundationModelsInsightWriter: InsightWriting {
    let generator: InsightTextGenerating
    let template: TemplateInsightWriter

    init(generator: InsightTextGenerating = SystemInsightTextGenerator(), template: TemplateInsightWriter = TemplateInsightWriter()) {
        self.generator = generator
        self.template = template
    }

    var isModelAvailable: Bool { generator.isAvailable }

    func insights(for facts: InsightFacts) async -> DailyInsights {
        let base = template.insights(for: facts)
        guard generator.isAvailable,
              let text = try? await generator.generate(for: facts),
              InsightTextValidator.isValid(text, for: facts) else { return base }
        return Self.applying(text, to: base, facts: facts)
    }

    /// The template's day with the validated texts in place, each marked as written on this device.
    static func applying(_ text: GeneratedInsightText, to base: DailyInsights, facts: InsightFacts) -> DailyInsights {
        var result = base
        let mood = text.moodLine.trimmingCharacters(in: .whitespacesAndNewlines)
        result.moodLine = mood
        result.moodLineIsAI = true
        result.notificationBody = mood
        for index in result.tiles.indices {
            switch result.tiles[index].kind {
            case .energy where InsightTextValidator.expectsEnergy(facts):
                if let energy = text.energy?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    result.tiles[index].body = energy
                    result.tiles[index].isAI = true
                }
            case .pattern:
                if let pattern = text.pattern?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    result.tiles[index].body = pattern
                    result.tiles[index].isAI = true
                }
            default:
                break
            }
        }
        return result
    }

    // MARK: - Prompt

    static let instructions = """
    You write short daily notes for a private cycle and symptom log kept on this phone. \
    Use only the facts given. Write plain, warm, calm sentences in the second person. \
    Name only tags listed in the facts and use only numbers listed in the facts. \
    Do not give medical advice, causes, diagnoses or treatments. \
    Do not mention fertility, pregnancy or birth control. \
    No emoji, no dashes, no nicknames. Leave a field empty when it is not asked for.
    """

    static let maximumResponseTokens = 220

    /// The whole prompt: the day's facts as short labelled lines, then which fields to write. Nothing else.
    static func prompt(for facts: InsightFacts) -> String {
        var lines = ["Facts:", "Mode: \(facts.mode.title)"]
        if let phase = facts.phase { lines.append("Phase: \(phase.rawValue)") }
        if let day = facts.cycleDay { lines.append("Cycle day: \(day)") }
        if let late = facts.periodLateDays {
            lines.append("Period later than estimated by days: \(late)")
        } else if let until = facts.daysUntilPeriod {
            lines.append("Days until the estimated next period: \(until)")
        }
        if !facts.recentTags.isEmpty {
            let tags = facts.recentTags.map { "\($0.label) (\($0.count))" }.joined(separator: ", ")
            lines.append("Tags in the last \(InsightFacts.recentDays) days, with counts: \(tags)")
        }
        lines.append("Tags logged today: \(facts.tagsLoggedToday)")
        if let months = facts.monthsSinceLastPeriod { lines.append("Months since the last period: \(months)") }
        if let thisWeek = facts.hotFlashesThisWeek {
            lines.append("Hot flashes this week: \(thisWeek), last week: \(facts.hotFlashesLastWeek ?? 0)")
        }
        if let sleep = facts.sleepAverageHours { lines.append("Average sleep in hours: \(SleepInsights.rounded(sleep))") }
        if let pattern = facts.pattern { lines.append("Pattern: \(pattern.sentence)") }

        var asks = ["moodLine: one sentence for today, under \(InsightTextValidator.moodLineLimit) characters"]
        if InsightTextValidator.expectsEnergy(facts) {
            asks.append("energy: one or two sentences about energy in this phase, under \(InsightTextValidator.bodyLimit) characters")
        } else {
            asks.append("energy: leave empty")
        }
        if facts.pattern != nil {
            asks.append("pattern: the pattern in your own words, under \(InsightTextValidator.bodyLimit) characters")
        } else {
            asks.append("pattern: leave empty")
        }
        return (lines + ["Write:"] + asks.map { "- \($0)" }).joined(separator: "\n")
    }
}

// MARK: - System model

@Generable
struct GeneratedDailyTiles {
    @Guide(description: "One warm, plain sentence for today, under 90 characters.")
    var moodLine: String
    @Guide(description: "One or two short sentences about energy today, under 140 characters, or empty.")
    var energy: String
    @Guide(description: "The pattern in your own words, under 140 characters, or empty.")
    var pattern: String
}

enum InsightGenerationError: Error {
    case unavailable
}

/// The Foundation Models generator. Checks availability at runtime: the model needs an eligible device with
/// Apple Intelligence on and ready.
struct SystemInsightTextGenerator: InsightTextGenerating {
    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func generate(for facts: InsightFacts) async throws -> GeneratedInsightText {
        guard isAvailable else { throw InsightGenerationError.unavailable }
        let session = LanguageModelSession(instructions: FoundationModelsInsightWriter.instructions)
        let options = GenerationOptions(temperature: 0.4,
                                        maximumResponseTokens: FoundationModelsInsightWriter.maximumResponseTokens)
        let response = try await session.respond(to: FoundationModelsInsightWriter.prompt(for: facts),
                                                 generating: GeneratedDailyTiles.self,
                                                 options: options)
        let tiles = response.content
        func optional(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return GeneratedInsightText(moodLine: tiles.moodLine, energy: optional(tiles.energy), pattern: optional(tiles.pattern))
    }
}
