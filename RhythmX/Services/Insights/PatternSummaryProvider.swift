//  PatternSummaryProvider.swift
//  The optional on-device summary behind the Patterns segment. Apple's Foundation Models framework
//  (iOS 26 and later, only where the system model is available) writes a short summary from the
//  PatternFinder findings. It is given finding sentences and evidence only: never dates, notes or raw
//  tag strings. The system model can be unavailable on a device (Apple Intelligence off or not
//  supported), so availability is checked at runtime and the protocol lets tests use a fake.

import Foundation
import FoundationModels

protocol PatternSummarizing {
    var isAvailable: Bool { get }
    /// `question` is one of the suggested questions, appended to the facts. Nil asks for a plain summary.
    func summarize(_ findings: [PatternFinding], question: String?) async throws -> String
}

extension PatternSummarizing {
    func summarize(_ findings: [PatternFinding]) async throws -> String {
        try await summarize(findings, question: nil)
    }
}

enum PatternSummaryError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The on-device summary is not available on this device."
        }
    }
}

struct PatternSummaryProvider: PatternSummarizing {
    static let onDeviceLabel = "Summary written on this device"
    static let disclaimer = "Not medical advice"
    static let summaryLimit = 400

    static let instructions = """
    You write a short, friendly summary of patterns noticed in the person's own health log. \
    Address the person as you. Use only the facts listed. Do not add causes, advice, or anything the facts do not say. \
    Write numbers with digits, and only the numbers in the facts. No dashes, lists, or emoji. \
    Two or three plain sentences. If asked a question the facts cannot answer, say so briefly.
    """

    /// Whether the system model can run now; tests pass a fixed answer.
    private let availability: () -> Bool
    /// Runs the model with the instructions and the prompt; tests pass a fake.
    private let generate: (_ instructions: String, _ prompt: String) async throws -> String

    init(availability: (() -> Bool)? = nil,
         generate: ((_ instructions: String, _ prompt: String) async throws -> String)? = nil) {
        self.availability = availability ?? {
            if case .available = SystemLanguageModel.default.availability { return true }
            return false
        }
        self.generate = generate ?? { instructions, prompt in
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond(to: prompt).content
        }
    }

    /// The whole prompt: finding sentences with their evidence, then the optional question. Nothing else.
    static func prompt(for findings: [PatternFinding], question: String?) -> String {
        var lines = ["Facts:"]
        lines += findings.map { "- \($0.sentence) (\($0.evidence))" }
        if let question, !question.isEmpty {
            lines.append("Question: \(question)")
        }
        return lines.joined(separator: "\n")
    }

    static func suggestedQuestions(for mode: TrackingMode) -> [String] {
        switch mode {
        case .cycle:
            return ["What changes before my period?", "What comes up most often?"]
        case .planning:
            return ["What changes around ovulation?", "What comes up most often?"]
        case .menopause:
            return ["What came up most in recent weeks?", "Is anything easing off?"]
        }
    }

    /// The findings as plain sentences, shown when the model's text does not pass the checks.
    static func plainText(for findings: [PatternFinding]) -> String {
        findings.map { "\($0.sentence), in \($0.evidence)." }.joined(separator: " ")
    }

    /// The model's text when it passes the same rules as the daily insights (`InsightTextValidator`): no dash,
    /// markup or emoji, no blocked word the findings do not use, only the findings' tags and numbers, and not
    /// too long. Otherwise the plain findings.
    static func checked(_ text: String, findings: [PatternFinding]) -> String {
        let source = findings.map { "\($0.sentence) \($0.evidence)" }.joined(separator: " ")
        let labels = Set(findings.map { TagParser.label(for: $0.tag) })
        let ok = InsightTextValidator.isAcceptable(text, limit: summaryLimit, allowedTagLabels: labels,
                                                   allowedNumbers: InsightTextValidator.numbers(in: source),
                                                   sourceText: source)
        return ok ? text.trimmingCharacters(in: .whitespacesAndNewlines) : plainText(for: findings)
    }

    var isAvailable: Bool { availability() }

    func summarize(_ findings: [PatternFinding], question: String?) async throws -> String {
        guard availability() else { throw PatternSummaryError.unavailable }
        let raw = try await generate(Self.instructions, Self.prompt(for: findings, question: question))
        return Self.checked(raw, findings: findings)
    }
}
