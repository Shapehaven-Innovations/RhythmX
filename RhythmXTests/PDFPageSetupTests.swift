import PDFKit
import XCTest
@testable import RhythmX

/// Paper, orientation and the size information on the export screen. Every combination of paper,
/// orientation and document renders exactly one page of the exact size.
@MainActor
final class PDFPageSetupTests: XCTestCase {
    private let calendar = Calendar.current
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14))!

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Sizes

    func testPaperSizesInPointsAndLandscapeSwaps() {
        XCTAssertEqual(PaperSize.letter.size(.portrait), CGSize(width: 612, height: 792))
        XCTAssertEqual(PaperSize.letter.size(.landscape), CGSize(width: 792, height: 612))
        XCTAssertEqual(PaperSize.a4.size(.portrait), CGSize(width: 595, height: 842))
        XCTAssertEqual(PaperSize.a4.size(.landscape), CGSize(width: 842, height: 595))
        XCTAssertEqual(PaperSize.letter.size, PaperSize.letter.size(.portrait), "the portrait size is unchanged")
    }

    // MARK: - PDFPageInfo

    func testLabelsInInchesAndMillimeters() {
        XCTAssertEqual(PDFPageInfo(paper: .letter, orientation: .portrait, unit: .inches).label, "Letter, 8.5 x 11 in")
        XCTAssertEqual(PDFPageInfo(paper: .letter, orientation: .landscape, unit: .inches).label, "Letter, 11 x 8.5 in")
        XCTAssertEqual(PDFPageInfo(paper: .a4, orientation: .portrait, unit: .millimeters).label, "A4, 210 x 297 mm")
        XCTAssertEqual(PDFPageInfo(paper: .a4, orientation: .landscape, unit: .millimeters).label, "A4, 297 x 210 mm")
        XCTAssertEqual(PDFPageInfo(paper: .letter, orientation: .portrait, unit: .millimeters).dimensions, "216 x 279 mm")
        XCTAssertEqual(PDFPageInfo(paper: .letter, orientation: .landscape, unit: .millimeters).dimensions, "279 x 216 mm")
        XCTAssertEqual(PDFPageInfo(paper: .a4, orientation: .portrait, unit: .inches).dimensions, "8.3 x 11.7 in")
        XCTAssertEqual(PDFPageInfo(paper: .a4, orientation: .landscape, unit: .inches).dimensions, "11.7 x 8.3 in")
    }

    func testUnitFollowsRegion() {
        XCTAssertEqual(PDFPageInfo.unit(for: Locale(identifier: "en_US")), .inches)
        XCTAssertEqual(PDFPageInfo.unit(for: Locale(identifier: "en_LR")), .inches)
        XCTAssertEqual(PDFPageInfo.unit(for: Locale(identifier: "my_MM")), .inches)
        XCTAssertEqual(PDFPageInfo.unit(for: Locale(identifier: "en_GB")), .millimeters)
        XCTAssertEqual(PDFPageInfo.unit(for: Locale(identifier: "de_DE")), .millimeters)
        XCTAssertEqual(PDFPageInfo.unit(for: Locale(identifier: "en_CA")), .millimeters)
        XCTAssertEqual(PDFPageInfo(paper: .a4, orientation: .portrait, locale: Locale(identifier: "fr_FR")).label, "A4, 210 x 297 mm")
        XCTAssertEqual(PDFPageInfo(paper: .letter, orientation: .portrait, locale: Locale(identifier: "en_US")).label, "Letter, 8.5 x 11 in")
    }

    func testPageSizeAspectRatioPageCountAndScale() {
        let letter = PDFPageInfo(paper: .letter, orientation: .portrait, unit: .inches)
        XCTAssertEqual(letter.pageSize, CGSize(width: 612, height: 792))
        XCTAssertEqual(letter.aspectRatio, 612.0 / 792.0, accuracy: 0.0001)
        let a4Landscape = PDFPageInfo(paper: .a4, orientation: .landscape, unit: .millimeters)
        XCTAssertEqual(a4Landscape.pageSize, CGSize(width: 842, height: 595))
        XCTAssertEqual(a4Landscape.aspectRatio, 842.0 / 595.0, accuracy: 0.0001)

        XCTAssertEqual(PDFPageInfo.pageCountText(1), "1 page")
        XCTAssertEqual(PDFPageInfo.pageCountText(2), "2 pages")

        // No percentage: how small the preview is depends on the iPhone model, so the hint only states
        // that it is reduced and which paper the file is sized for.
        XCTAssertEqual(letter.scaleHint, "Preview is reduced to fit. The PDF prints at full size on Letter paper.")
        XCTAssertEqual(a4Landscape.scaleHint, "Preview is reduced to fit. The PDF prints at full size on A4 paper.")
        XCTAssertFalse(letter.scaleHint.contains("%"))
    }

    // MARK: - Remembered orientation

    func testOrientationDefaultsAndIsRememberedPerDocument() {
        let keys = [AppSettings.calendarPDFOrientationKey, AppSettings.reportPDFOrientationKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }

        let settings = AppSettings()
        XCTAssertEqual(settings.pdfOrientation(for: .calendar), .landscape)
        XCTAssertEqual(settings.pdfOrientation(for: .report), .portrait)

        settings.setPDFOrientation(.landscape, for: .report)
        XCTAssertEqual(settings.pdfOrientation(for: .report), .landscape)
        XCTAssertEqual(settings.pdfOrientation(for: .calendar), .landscape)
        settings.setPDFOrientation(.portrait, for: .calendar)
        XCTAssertEqual(AppSettings().pdfOrientation(for: .calendar), .portrait, "stored, so a new screen remembers it")
        XCTAssertEqual(AppSettings().pdfOrientation(for: .report), .landscape)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettings.calendarPDFOrientationKey), "portrait",
                       "a plain string value")

        UserDefaults.standard.set("sideways", forKey: AppSettings.reportPDFOrientationKey)
        XCTAssertEqual(AppSettings().pdfOrientation(for: .report), .portrait, "an unknown value falls back to the default")
    }

    // MARK: - Every combination is one page of the exact size

    private func assertOnePage(_ data: Data, size: CGSize, _ label: String,
                               file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let doc = try XCTUnwrap(PDFDocument(data: data), "\(label) is a PDF", file: file, line: line)
        XCTAssertEqual(doc.pageCount, 1, "\(label): one page", file: file, line: line)
        let page = try XCTUnwrap(doc.page(at: 0), file: file, line: line)
        let bounds = page.bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, size.width, accuracy: 0.01, "\(label): width", file: file, line: line)
        XCTAssertEqual(bounds.height, size.height, accuracy: 0.01, "\(label): height", file: file, line: line)
        return page.string ?? ""
    }

    /// The footer line is the lowest text on the page (every other glyph sits above it) and nothing is drawn
    /// outside the margins.
    private func assertFooterIsLastAndNothingClips(_ data: Data, footer: String, _ label: String,
                                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let doc = try XCTUnwrap(PDFDocument(data: data), file: file, line: line)
        let page = try XCTUnwrap(doc.page(at: 0), file: file, line: line)
        let found = try XCTUnwrap(doc.findString(footer, withOptions: []).first, "\(label): footer is on the page",
                                  file: file, line: line)
        let footerBox = found.bounds(for: page)
        XCTAssertGreaterThan(page.numberOfCharacters, 50, "\(label): the page has text to check", file: file, line: line)
        let inside = page.bounds(for: .mediaBox).insetBy(dx: PDFDrawing.margin - 2, dy: PDFDrawing.margin - 2)
        for index in 0..<page.numberOfCharacters {
            let box = page.characterBounds(at: index)
            guard box.width > 0.5, box.height > 0.5 else { continue }
            let glyph = page.selection(for: NSRange(location: index, length: 1))?.string ?? "?"
            guard !glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            XCTAssertTrue(inside.contains(box), "\(label): '\(glyph)' at \(box) is outside the margins", file: file, line: line)
            if !footerBox.insetBy(dx: -1, dy: -1).contains(box) {
                XCTAssertGreaterThanOrEqual(box.minY, footerBox.maxY,
                                            "\(label): '\(glyph)' at \(box) is level with or below the footer", file: file, line: line)
            }
        }
    }

    private func block(start: Date, length: Int, tags: String = "") -> ArchivedDataBlock {
        var events = CycleGenerator.events(startDate: start, cycleLength: length)
        if !tags.isEmpty { events[1].tags = tags }
        let grouped = Dictionary(grouping: events, by: { $0.eventType })
            .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) }
        return ArchivedDataBlock(date: start, groupedEvents: grouped)
    }

    func testCalendarEveryPaperAndOrientationIsOnePageOfExactSize() throws {
        var monday = Calendar(identifier: .gregorian)
        monday.firstWeekday = 2
        let october = date(2026, 10, 1)
        // August 2026 starts on a Saturday: six rows when weeks start on Monday.
        let august = monday.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        XCTAssertEqual(CalendarMonthModel(containing: august, calendar: monday).cells.count / 7, 6, "fixture is a six-row month")

        let full = CalendarPDFRenderer(events: CycleGenerator.events(startDate: date(2026, 10, 3), cycleLength: 28), archivedBlocks: [])
        let sparse = CalendarPDFRenderer(events: [], archivedBlocks: [])
        let sixRows = CalendarPDFRenderer(events: CycleGenerator.events(startDate: date(2026, 8, 3), cycleLength: 28),
                                          archivedBlocks: [], calendar: monday)
        for paper in PaperSize.allCases {
            for orientation in PaperSize.Orientation.allCases {
                let size = paper.size(orientation)
                for (label, renderer, month) in [("full", full, october), ("sparse", sparse, october), ("six rows", sixRows, august)] {
                    let name = "calendar \(label) \(paper) \(orientation)"
                    let text = try assertOnePage(renderer.render(month: month, paper: paper, orientation: orientation,
                                                                 lightTints: false, today: today), size: size, name)
                    XCTAssertFalse(text.localizedCaseInsensitiveContains("RhythmX"), "\(name): no app name on the calendar")
                    XCTAssertTrue(text.contains("Predictions are estimates and are not birth control."), "\(name): footer")
                    XCTAssertTrue(text.contains("Predicted period"), "\(name): legend")
                    XCTAssertTrue(text.contains("31"), "\(name): every day is drawn")
                    try assertFooterIsLastAndNothingClips(renderer.render(month: month, paper: paper, orientation: orientation,
                                                                          lightTints: false, today: today),
                                                          footer: "Predictions are estimates and are not birth control.", name)
                }
            }
        }
    }

    func testReportsEveryPaperAndOrientationAreOnePageOfExactSize() throws {
        let blocks = [block(start: date(2026, 5, 3), length: 27, tags: "Symptom:Cramps, Symptom:Headache"),
                      block(start: date(2026, 5, 30), length: 29, tags: "Symptom:Bloating"),
                      block(start: date(2026, 6, 28), length: 48, tags: "Symptom:Fatigue"),
                      block(start: date(2026, 8, 15), length: 28, tags: "Symptom:Back Pain")]
        let current = CycleGenerator.events(startDate: date(2026, 10, 3), cycleLength: 28)
        let full = DoctorReportBuilder.make(events: current, archivedBlocks: blocks, mode: .cycle, today: today)
        let sparse = DoctorReportBuilder.make(events: current, archivedBlocks: [blocks[0]], mode: .cycle, today: today)
        let menopauseEvents = [Event(eventType: .menstrual, date: date(2026, 2, 14), note: "")] + (0..<30).map { offset in
            Event(eventType: .follicular, date: calendar.date(byAdding: .day, value: -offset, to: today)!, note: "",
                  tags: "Menopause:Hot Flashes, Menopause:Night Sweats", mode: .menopause)
        }
        let menopause = DoctorReportBuilder.make(events: menopauseEvents, archivedBlocks: [], mode: .menopause, today: today)
        XCTAssertTrue(full.hasEnoughData)
        XCTAssertFalse(sparse.hasEnoughData)

        let renderer = DoctorReportPDFRenderer(today: today)
        for paper in PaperSize.allCases {
            for orientation in PaperSize.Orientation.allCases {
                let size = paper.size(orientation)
                for (label, report) in [("full", full), ("sparse", sparse), ("menopause", menopause)] {
                    let name = "report \(label) \(paper) \(orientation)"
                    let text = try assertOnePage(renderer.render(report, paper: paper, orientation: orientation,
                                                                 name: "Jane Example", birthDate: date(1988, 4, 23)),
                                                 size: size, name)
                    try assertFooterIsLastAndNothingClips(renderer.render(report, paper: paper, orientation: orientation,
                                                                          name: "Jane Example", birthDate: date(1988, 4, 23)),
                                                          footer: DoctorReportPDFRenderer.disclaimer, name)
                    XCTAssertTrue(text.contains("Jane Example"), "\(name): the name is printed")
                    switch label {
                    case "full":
                        for part in ["Average cycle", "Most logged symptoms", "Cramps", "Cycle lengths", "Period start dates", "48"] {
                            XCTAssertTrue(text.contains(part), "\(name): \(part)")
                        }
                    case "sparse":
                        XCTAssertTrue(text.contains("Log a few more cycles"), "\(name): sparse message")
                    default:
                        XCTAssertTrue(text.contains("Months since last period"), "\(name): menopause tiles")
                        XCTAssertTrue(text.contains("Poor sleep"), "\(name): the last chart is on the page")
                    }
                }
            }
        }
    }

    func testLandscapeReportCarriesTheAppIconImage() {
        let report = DoctorReportBuilder.make(events: [], archivedBlocks: [], mode: .cycle, today: today)
        let data = DoctorReportPDFRenderer(today: today).render(report, paper: .letter, orientation: .landscape, name: nil, birthDate: nil)
        XCTAssertNotNil(data.range(of: Data("/Subtype /Image".utf8)), "the landscape header draws the app icon image")
    }
}
