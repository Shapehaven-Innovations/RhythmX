import XCTest
@testable import RhythmX

/// Task 10B: the on-device summary card receives only PatternFinder facts, and hides when unavailable.
final class PatternSummaryTests: XCTestCase {
    private let calendar = Calendar.current
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14))!

    /// Captures what the view model hands the summarizer.
    private final class FakeSummarizer: PatternSummarizing {
        var isAvailable: Bool
        var reply = "A short summary."
        var receivedFindings: [PatternFinding] = []
        var receivedQuestion: String?
        var prompt: String?

        init(isAvailable: Bool) { self.isAvailable = isAvailable }

        func summarize(_ findings: [PatternFinding], question: String?) async throws -> String {
            receivedFindings = findings
            receivedQuestion = question
            prompt = PatternSummaryProvider.prompt(for: findings, question: question)
            return reply
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Four archived 28-day cycles with Cramps on days 1 to 3 and a note full of things that must never reach the model.
    private func crampBlocks() -> [ArchivedDataBlock] {
        (0..<4).map { i in
            let start = date(2026, 1 + i, 1)
            let events = (1...28).map { day -> Event in
                let phase: Event.EventType = day <= 5 ? .menstrual : day <= 13 ? .follicular : day <= 16 ? .ovulation : .luteal
                return Event(eventType: phase,
                             date: calendar.date(byAdding: .day, value: day - 1, to: start)!,
                             note: "Doctor visit at Riverside Clinic 2026-03-14",
                             tags: day <= 3 ? "Symptom:Cramps" : "")
            }
            let grouped = Dictionary(grouping: events) { $0.eventType }
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) }
            return ArchivedDataBlock(date: calendar.date(byAdding: .day, value: 28, to: start)!, groupedEvents: grouped)
        }
    }

    // MARK: - What the summarizer sees

    func testSummarizerReceivesOnlyFindingSentences() async throws {
        let fake = FakeSummarizer(isAvailable: true)
        let vm = TagPatternsViewModel(events: [], archivedBlocks: crampBlocks(), mode: .cycle, summarizer: fake, today: today)
        XCTAssertFalse(vm.findings.isEmpty)

        let reply = try await vm.summary(question: nil)
        XCTAssertEqual(reply, "A short summary.")
        XCTAssertEqual(fake.receivedFindings, vm.findings)

        let prompt = try XCTUnwrap(fake.prompt)
        XCTAssertTrue(prompt.contains("Cramps came up on days 1 to 3"))
        XCTAssertTrue(prompt.contains("4 of your last 4 cycles"))
        XCTAssertFalse(prompt.contains("2026"), "no dates")
        XCTAssertFalse(prompt.contains("Jan"), "no dates")
        XCTAssertFalse(prompt.contains("Doctor visit"), "no note text")
        XCTAssertFalse(prompt.contains("Riverside"), "no note text")
        XCTAssertFalse(prompt.contains("Symptom:Cramps"), "no raw tag strings")
    }

    func testPromptIsBuiltFromSentencesEvidenceAndTheQuestionOnly() {
        let findings = [
            PatternFinding(id: "a", sentence: "Headache appears on days 24 to 27, in your luteal phase", evidence: "4 of your last 6 cycles", tag: "Symptom:Headache"),
            PatternFinding(id: "b", sentence: "Cramps appear on days 1 to 3, in your menstrual phase", evidence: "5 of your last 6 cycles", tag: "Symptom:Cramps")
        ]
        let plain = PatternSummaryProvider.prompt(for: findings, question: nil)
        XCTAssertTrue(plain.contains("Headache appears on days 24 to 27, in your luteal phase (4 of your last 6 cycles)"))
        XCTAssertTrue(plain.contains("Cramps appear on days 1 to 3, in your menstrual phase (5 of your last 6 cycles)"))
        XCTAssertFalse(plain.contains("Symptom:"))
        XCTAssertFalse(plain.contains("What changes before my period?"))

        let asked = PatternSummaryProvider.prompt(for: findings, question: "What changes before my period?")
        XCTAssertTrue(asked.hasSuffix("What changes before my period?"))
        XCTAssertTrue(asked.hasPrefix(plain))

        XCTAssertEqual(PatternSummaryProvider.suggestedQuestions(for: .cycle).first, "What changes before my period?")
        XCTAssertFalse(PatternSummaryProvider.suggestedQuestions(for: .menopause).contains("What changes before my period?"))
    }

    func testSummaryWithoutFindingsNeverCallsTheModel() async throws {
        let fake = FakeSummarizer(isAvailable: true)
        let vm = TagPatternsViewModel(events: [], archivedBlocks: [], mode: .cycle, summarizer: fake, today: today)

        let reply = try await vm.summary(question: nil)
        XCTAssertEqual(reply, "")
        XCTAssertNil(fake.prompt, "nothing to summarize, so the model is not asked and cannot invent facts")
    }

    // MARK: - Card visibility

    func testUnavailableSummarizerHidesCard() {
        let blocks = crampBlocks()
        let hidden = TagPatternsViewModel(events: [], archivedBlocks: blocks, mode: .cycle,
                                          summarizer: FakeSummarizer(isAvailable: false), today: today)
        XCTAssertFalse(hidden.showsSummary)
        XCTAssertEqual(hidden.findings.count, 1, "the deterministic findings still show")
        XCTAssertFalse(hidden.heatmap.isEmpty)

        let shown = TagPatternsViewModel(events: [], archivedBlocks: blocks, mode: .cycle,
                                         summarizer: FakeSummarizer(isAvailable: true), today: today)
        XCTAssertTrue(shown.showsSummary)

        let noFacts = TagPatternsViewModel(events: [], archivedBlocks: [], mode: .cycle,
                                           summarizer: FakeSummarizer(isAvailable: true), today: today)
        XCTAssertFalse(noFacts.showsSummary, "with no findings there is nothing to summarize")
    }

    func testRealProviderIsSafeWhereFoundationModelsIsMissing() async {
        let provider = PatternSummaryProvider()
        guard !provider.isAvailable else { return }   // an iOS 26 device with Apple Intelligence on
        do {
            _ = try await provider.summarize([PatternFinding(id: "a", sentence: "s", evidence: "e", tag: "t")], question: nil)
            XCTFail("an unavailable provider must throw, not return text")
        } catch {
            XCTAssertTrue(error is PatternSummaryError)
        }
    }

    // MARK: - Checking what the model wrote

    private let checkFindings = [
        PatternFinding(id: "a", sentence: "Cramps came up on days 1 to 3, in your menstrual phase",
                       evidence: "4 of your last 4 cycles", tag: "Symptom:Cramps")
    ]

    private func provider(reply: String) -> PatternSummaryProvider {
        PatternSummaryProvider(availability: { true }, generate: { _, _ in reply })
    }

    func testAcceptableModelTextIsShown() async throws {
        let reply = "Cramps came up early in your cycle, on days 1 to 3, in 4 of your last 4 cycles."
        let text = try await provider(reply: reply).summarize(checkFindings, question: nil)
        XCTAssertEqual(text, reply)
    }

    func testModelTextThatBreaksTheRulesFallsBackToTheFindings() async throws {
        let fallback = PatternSummaryProvider.plainText(for: checkFindings)
        XCTAssertEqual(fallback, "Cramps came up on days 1 to 3, in your menstrual phase, in 4 of your last 4 cycles.")
        for bad in ["Cramps came up \u{2014} often.", "Cramps came up a lot \u{1F319}", "Ask your doctor about Cramps.",
                    "Cramps came up on 7 days.", "Cramps came up three times.", "Headache came up too.",
                    "She logged Cramps.", String(repeating: "Cramps came up. ", count: 40)] {
            let text = try await provider(reply: bad).summarize(checkFindings, question: nil)
            XCTAssertEqual(text, fallback, bad)
        }
    }

    func testInstructionsAreGenderNeutral() {
        let words = PatternSummaryProvider.instructions.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
        for word in ["her", "she", "hers", "herself", "woman", "women"] {
            XCTAssertFalse(words.contains(word), word)
        }
        XCTAssertTrue(PatternSummaryProvider.instructions.contains("the person's own health log"))
    }

    func testDefaultSummarizeHasNoQuestion() async throws {
        let fake = FakeSummarizer(isAvailable: true)
        _ = try await fake.summarize([PatternFinding(id: "a", sentence: "s", evidence: "e", tag: "t")])
        XCTAssertNil(fake.receivedQuestion)
    }
}
