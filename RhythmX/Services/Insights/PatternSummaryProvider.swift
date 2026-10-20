//  PatternSummaryProvider.swift
//  The optional on-device summary behind the Patterns segment. Apple's Foundation Models framework
//  (iOS 26 and later, only where the system model is available) writes a short summary from the
//  PatternFinder findings. It is given finding sentences and evidence only: never dates, notes or raw
//  tag strings. The app targets iOS 18, so everything model-related is guarded and the protocol lets
//  tests use a fake.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

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

    static let instructions = """
    You write a short, friendly summary of patterns a person noticed in her own health log. \
    Use only the facts listed. Do not add causes, advice, or anything the facts do not say. \
    Two or three plain sentences. If asked a question the facts cannot answer, say so briefly.
    """

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

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    func summarize(_ findings: [PatternFinding], question: String?) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw PatternSummaryError.unavailable
            }
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: Self.prompt(for: findings, question: question))
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw PatternSummaryError.unavailable
    }
}
