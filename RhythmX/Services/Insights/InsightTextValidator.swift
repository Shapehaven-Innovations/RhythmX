//  InsightTextValidator.swift
//  The check every on-device text passes before it is shown. Anything that fails sends the whole day back to
//  the template: a tag or number the facts do not hold (spelled-out numbers included), a blocked word
//  (diagnosis, treatment, fertility or birth control claims, ovulation or period timing claims, gendered
//  words), an emoji, a dash of any kind used as an aside, markup, or text that is too long.

import Foundation

/// The texts the on-device model writes for a day. Nil fields were not asked for or came back empty.
struct GeneratedInsightText: Equatable {
    var moodLine: String
    var energy: String?
    var pattern: String?
}

enum InsightTextValidator {
    static let moodLineLimit = 90
    static let bodyLimit = 140

    /// Matched without case on word boundaries. A match is allowed only when the same word is in the facts the
    /// writer was given (`sourceText`), for example "ovulation" in "your ovulation phase".
    static let blockedPatterns: [String] = [
        #"diagnos\w*"#, #"cure[sd]?"#, #"curing"#, #"treat\w*"#, #"prescri\w*"#, #"medic\w*"#,
        #"dos(e|es|age)"#, #"doctor\w*"#, #"physician\w*"#, #"disease\w*"#, #"disorder\w*"#, #"syndrome\w*"#,
        #"infection\w*"#, #"cancer\w*"#, #"condition\w*"#, #"symptom of"#, #"emergency"#,
        #"pregnan\w*"#, #"conceiv\w*"#, #"contracep\w*"#, #"birth control"#, #"fertil\w*"#, #"safe\w*"#,
        #"unprotected"#, #"guarantee\w*"#, #"pills?"#, #"supplement\w*"#, #"advice"#, #"advise\w*"#,
        #"you should"#, #"you must"#,
        #"goddess\w*"#, #"queen\w*"#, #"ladies"#, #"lady"#, #"girls?"#, #"wom[ae]n"#, #"feminine"#, #"sexy"#,
        #"she"#, #"her"#, #"hers"#, #"herself"#,
        // Timing claims the facts never make in these words: ovulation and when a period starts.
        #"ovulat\w*"#,
        #"period\s+(?:is\s+|will\s+|should\s+|may\s+|might\s+|could\s+|can\s+)?(?:be\s+)?(?:start\w*|late|coming|due|arriv\w*|begin\w*|expected|near|soon|here|overdue)"#,
        // Numbers must come from the facts as digits, so spelled-out numbers are not allowed.
        #"zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen"#,
        #"sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety"#,
        #"hundreds?|thousands?|dozens?|once|twice|thrice|couple"#
    ]

    /// Dashes of every kind used as an aside, and markup or symbols a plain sentence does not need.
    static let forbiddenSubstrings: [String] = [
        "--", " - ", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}",
        "\u{FE58}", "\u{FE63}", "\u{FF0D}", "\u{2022}", "\u{00B7}",
        "*", "#", "_", "`", "~", "|", "<", ">", "[", "]", "{", "}", "^", "\\", "@"
    ]

    private static let blocked: [NSRegularExpression] = blockedPatterns.compactMap {
        try? NSRegularExpression(pattern: "\\b(?:\($0))\\b", options: [.caseInsensitive])
    }

    /// Every label in the tag library, longest first.
    private static let libraryLabels: [String] = Array(Set(TagLibrary.tags.values.flatMap { $0 }))
        .sorted { $0.count > $1.count }

    static func isValid(_ text: GeneratedInsightText, for facts: InsightFacts) -> Bool {
        guard isAcceptable(text.moodLine, limit: moodLineLimit, facts: facts) else { return false }
        if expectsEnergy(facts) {
            guard let energy = text.energy, isAcceptable(energy, limit: bodyLimit, facts: facts) else { return false }
        }
        if facts.pattern != nil {
            guard let pattern = text.pattern, isAcceptable(pattern, limit: bodyLimit, facts: facts) else { return false }
        }
        return true
    }

    /// The energy tile exists (Cycle and Planning with a phase), so the model writes its text.
    static func expectsEnergy(_ facts: InsightFacts) -> Bool {
        facts.mode != .menopause && facts.phase != nil
    }

    static func isAcceptable(_ text: String, limit: Int, facts: InsightFacts) -> Bool {
        isAcceptable(text, limit: limit, allowedTagLabels: facts.allowedTagLabels, allowedNumbers: facts.allowedNumbers,
                     sourceText: sourceText(for: facts))
    }

    /// The facts' own words a text may repeat: the phase name and the pattern sentence.
    static func sourceText(for facts: InsightFacts) -> String {
        [facts.phase?.displayName, facts.pattern?.sentence].compactMap { $0 }.joined(separator: " ")
    }

    /// The shared rules: not empty, not longer than `limit`, no dash or markup, no emoji, no blocked word unless
    /// `sourceText` says it too, only the tag labels and digit numbers allowed.
    static func isAcceptable(_ text: String, limit: Int, allowedTagLabels: Set<String>, allowedNumbers: Set<String>,
                             sourceText: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= limit else { return false }
        guard !forbiddenSubstrings.contains(where: { trimmed.contains($0) }) else { return false }
        guard TagFormLogic.removingEmoji(trimmed) == trimmed else { return false }
        // A tag label it may name is a source too ("Ovulation Test Peak").
        let source = ([sourceText] + allowedTagLabels.sorted()).joined(separator: " ")
        guard !hasBlockedWord(trimmed, sourceText: source) else { return false }
        let allowedTags = Set(allowedTagLabels.map { $0.lowercased() })
        guard mentionedTagLabels(in: trimmed).allSatisfy({ allowedTags.contains($0.lowercased()) }) else { return false }
        guard numbers(in: trimmed).isSubset(of: allowedNumbers) else { return false }
        return true
    }

    /// True when `text` has a blocked word or phrase that `sourceText` does not have itself.
    static func hasBlockedWord(_ text: String, sourceText: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        let sourceRange = NSRange(sourceText.startIndex..., in: sourceText)
        for regex in blocked {
            for match in regex.matches(in: text, range: range) {
                guard let r = Range(match.range, in: text) else { return true }
                let word = NSRegularExpression.escapedPattern(for: String(text[r]))
                    .replacingOccurrences(of: " ", with: "\\s+")
                let same = try? NSRegularExpression(pattern: "\\b\(word)\\b", options: [.caseInsensitive])
                if same?.firstMatch(in: sourceText, range: sourceRange) == nil { return true }
            }
        }
        return false
    }

    /// Library tag labels named in `text`, on word boundaries and without case.
    static func mentionedTagLabels(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return libraryLabels.filter { label in
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: label))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
            return regex.firstMatch(in: text, range: range) != nil
        }
    }

    /// Numbers written with digits ("24", "6.7").
    static func numbers(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        })
    }
}
