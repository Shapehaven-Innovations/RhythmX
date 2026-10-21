//  InsightTileStream.swift
//  Streams an Apple Intelligence tile's text into the daily insight pull-up as the model writes it
//  (`LanguageModelSession.streamResponse`). Every partial text is checked as it arrives (no blocked word,
//  emoji, dash, unknown tag or number, nothing too long) and the finished text passes `InsightTextValidator`;
//  on unavailability, an error, an empty answer or any failed check, the template text is shown instead,
//  with the same reveal. Only the tiles the on-device writer words (pattern and energy) ever stream.

import Foundation
import FoundationModels

/// Streams the text for one tile. A protocol so tests can stand in for the system model.
protocol InsightTileStreaming {
    var isAvailable: Bool { get }
    /// Each element is the whole text so far.
    func stream(kind: DailyInsightTile.Kind, facts: InsightFacts) -> AsyncThrowingStream<String, Error>
}

struct InsightStreamResult: Equatable {
    var text: String
    /// True when the shown text was written on this device and passed every check.
    var isAI: Bool
}

enum InsightTileStreamRunner {
    /// Whether the model writes this tile for these facts (the same rule as `FoundationModelsInsightWriter`).
    static func streams(kind: DailyInsightTile.Kind, facts: InsightFacts) -> Bool {
        switch kind {
        case .pattern: return facts.pattern != nil
        case .energy:  return InsightTextValidator.expectsEnergy(facts)
        default:       return false
        }
    }

    /// A text that may still grow: the checks of the validator, except that it may be empty and a number at the
    /// very end may be unfinished ("2" on its way to "24").
    static func isAcceptablePartial(_ text: String, facts: InsightFacts) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var checked = trimmed
        if let last = trimmed.last, last.isNumber, let range = trimmed.range(of: #"\d+(?:\.\d*)?$"#, options: .regularExpression) {
            checked = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard trimmed.count <= InsightTextValidator.bodyLimit else { return false }
            if checked.isEmpty { return true }
        }
        return InsightTextValidator.isAcceptable(checked, limit: InsightTextValidator.bodyLimit, facts: facts)
    }

    /// Runs the stream, handing each accepted partial text to `onPartial`, and returns what to show at the end.
    static func run(streamer: InsightTileStreaming, kind: DailyInsightTile.Kind, facts: InsightFacts,
                    fallback: String, onPartial: @MainActor (String) -> Void) async -> InsightStreamResult {
        let fallbackResult = InsightStreamResult(text: fallback, isAI: false)
        guard streamer.isAvailable, streams(kind: kind, facts: facts) else { return fallbackResult }
        var latest = ""
        do {
            for try await partial in streamer.stream(kind: kind, facts: facts) {
                guard isAcceptablePartial(partial, facts: facts) else { return fallbackResult }
                latest = partial
                await onPartial(partial)
            }
        } catch {
            return fallbackResult
        }
        let final = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard InsightTextValidator.isAcceptable(final, limit: InsightTextValidator.bodyLimit, facts: facts) else {
            return fallbackResult
        }
        return InsightStreamResult(text: final, isAI: true)
    }
}

// MARK: - Prompt

extension FoundationModelsInsightWriter {
    /// The facts lines of `prompt(for:)` and one field to write.
    static func tilePrompt(for facts: InsightFacts, kind: DailyInsightTile.Kind) -> String {
        let factLines = prompt(for: facts).components(separatedBy: "\nWrite:").first ?? ""
        let ask: String
        switch kind {
        case .energy:
            ask = "text: one or two sentences about energy in this phase, under \(InsightTextValidator.bodyLimit) characters"
        default:
            ask = "text: the pattern in your own words, under \(InsightTextValidator.bodyLimit) characters"
        }
        return factLines + "\nWrite:\n- " + ask
    }
}

// MARK: - System model

@Generable
struct GeneratedTileText {
    @Guide(description: "One or two short, plain sentences, under 140 characters.")
    var text: String
}

/// The Foundation Models streamer. Checks availability at runtime.
struct SystemInsightTileStreamer: InsightTileStreaming {
    var isAvailable: Bool { SystemInsightTextGenerator().isAvailable }

    func stream(kind: DailyInsightTile.Kind, facts: InsightFacts) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard isAvailable else {
                    continuation.finish(throwing: InsightGenerationError.unavailable)
                    return
                }
                do {
                    let session = LanguageModelSession(instructions: FoundationModelsInsightWriter.instructions)
                    let options = GenerationOptions(temperature: 0.4,
                                                    maximumResponseTokens: FoundationModelsInsightWriter.maximumResponseTokens)
                    let stream = session.streamResponse(to: FoundationModelsInsightWriter.tilePrompt(for: facts, kind: kind),
                                                        generating: GeneratedTileText.self, options: options)
                    for try await snapshot in stream {
                        if let text = snapshot.content.text { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
