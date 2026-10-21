import PDFKit
import SwiftUI
import XCTest
@testable import RhythmX

/// Task 13: the printable monthly calendar PDF. One page, locale paper size, the app icon image and no app name.
@MainActor
final class CalendarPDFTests: XCTestCase {
    private let calendar = Calendar.current
    /// The month under test: October 2026.
    private let october = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14))!

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func renderer(events: [Event] = [], blocks: [ArchivedDataBlock] = []) -> CalendarPDFRenderer {
        CalendarPDFRenderer(events: events, archivedBlocks: blocks)
    }

    private func document(_ data: Data) throws -> PDFDocument {
        let doc = try XCTUnwrap(PDFDocument(data: data), "renderer output is a PDF")
        return doc
    }

    private func pageText(_ data: Data) throws -> String {
        let doc = try document(data)
        return try XCTUnwrap(doc.page(at: 0)?.string, "the page has extractable text")
    }

    // MARK: - Page count and size

    func testRendersExactlyOnePage() throws {
        let events = CycleGenerator.events(startDate: date(2026, 10, 3), cycleLength: 28)
        let data = renderer(events: events).render(month: october, paper: .letter, lightTints: false, today: today)
        XCTAssertEqual(try document(data).pageCount, 1)
    }

    func testPageSizeLetterAndA4() throws {
        XCTAssertEqual(PaperSize.letter.size, CGSize(width: 612, height: 792))
        XCTAssertEqual(PaperSize.a4.size, CGSize(width: 595, height: 842))

        let letter = try document(renderer().render(month: october, paper: .letter, lightTints: false, today: today))
        let letterBounds = try XCTUnwrap(letter.page(at: 0)?.bounds(for: .mediaBox))
        XCTAssertEqual(letterBounds.width, 612, accuracy: 0.5)
        XCTAssertEqual(letterBounds.height, 792, accuracy: 0.5)

        let a4 = try document(renderer().render(month: october, paper: .a4, lightTints: false, today: today))
        let a4Bounds = try XCTUnwrap(a4.page(at: 0)?.bounds(for: .mediaBox))
        XCTAssertEqual(a4Bounds.width, 595, accuracy: 0.5)
        XCTAssertEqual(a4Bounds.height, 842, accuracy: 0.5)
    }

    func testDefaultPaperFollowsRegion() {
        XCTAssertEqual(PaperSize.default(for: Locale(identifier: "en_US")), .letter)
        XCTAssertEqual(PaperSize.default(for: Locale(identifier: "en_GB")), .a4)
        XCTAssertEqual(PaperSize.default(for: Locale(identifier: "de_DE")), .a4)
        XCTAssertEqual(PaperSize.default(for: Locale(identifier: "fr_CA")), .a4)
    }

    /// A six-row month on a Monday-first calendar still fits one page, with the legend and footer drawn.
    func testSixRowMonthMondayFirstStaysOnOnePage() throws {
        var monday = Calendar(identifier: .gregorian)
        monday.firstWeekday = 2
        let august = monday.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let events = CycleGenerator.events(startDate: monday.date(from: DateComponents(year: 2026, month: 8, day: 3))!, cycleLength: 28)
        let pdf = CalendarPDFRenderer(events: events, archivedBlocks: [], calendar: monday)
        for paper in PaperSize.allCases {
            let data = pdf.render(month: august, paper: paper, lightTints: false, today: august)
            XCTAssertEqual(try document(data).pageCount, 1, "\(paper)")
            XCTAssertTrue(try pageText(data).contains("Phase calendar"), "legend line is on the page")
        }
    }

    // MARK: - Content

    func testNoAppNameTextOnPage() throws {
        let events = CycleGenerator.events(startDate: date(2026, 10, 3), cycleLength: 28)
        let text = try pageText(renderer(events: events).render(month: october, paper: .letter, lightTints: false, today: today))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("RhythmX"), "the printout carries the moon mark only, never the app name: \(text)")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("Rhythm X"))
    }

    func testContainsMonthTitleAndDayNumbers() throws {
        let events = CycleGenerator.events(startDate: date(2026, 10, 3), cycleLength: 28)
        let text = try pageText(renderer(events: events).render(month: october, paper: .a4, lightTints: true, today: today))
        XCTAssertTrue(text.contains("October 2026"), "month title: \(text)")
        for day in 1...31 {
            XCTAssertTrue(text.contains("\(day)"), "day \(day) is on the page")
        }
        XCTAssertTrue(text.contains("Menstrual"), "the legend names the phases")
        XCTAssertTrue(text.contains("Fertile window"))
    }

    func testSparseMonthWithNoEventsStillRenders() throws {
        let data = renderer().render(month: october, paper: .letter, lightTints: false, today: today)
        let doc = try document(data)
        XCTAssertEqual(doc.pageCount, 1)
        let text = try pageText(data)
        XCTAssertTrue(text.contains("October 2026"))
        XCTAssertTrue(text.contains("31"))
    }

    // MARK: - Cycle data only

    func testMenopauseEventsNeverShapeTheCalendar() throws {
        // A menopause carrier event on a day the cycle calendar would otherwise leave blank. The tinted-day
        // description lists the phase days, so a leaked menopause event would show up as an extra tinted day.
        let cycle = CycleGenerator.events(startDate: date(2026, 10, 3), cycleLength: 28)
        let carrier = Event(eventType: .ovulation, date: date(2026, 10, 1), note: "", tags: "Menopause:Hot Flashes", mode: .menopause)
        let r = renderer(events: cycle + [carrier])
        let days = r.tintedDays(month: october)
        XCTAssertNil(days[date(2026, 10, 1)], "a menopause day is never tinted by a cycle phase")
        XCTAssertEqual(days[date(2026, 10, 3)], .menstrual)
        XCTAssertEqual(days[date(2026, 10, 16)], .ovulation)
        XCTAssertFalse(r.fertileDays(month: october).contains(FertileWindow.dayKey(date(2026, 9, 26))),
                       "the fertile window comes from cycle ovulation days only")
    }

    func testPredictedDaysComeFromCycleBlocksOnly() {
        // Two archived cycles of 28 days: the next period is predicted 28 days after the last archived start.
        func block(start: Date, mode: TrackingMode? = nil) -> ArchivedDataBlock {
            let events = CycleGenerator.events(startDate: start, cycleLength: 28)
            let grouped = Dictionary(grouping: events, by: { $0.eventType })
                .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) }
            return ArchivedDataBlock(date: start, groupedEvents: grouped, mode: mode)
        }
        let blocks = [block(start: date(2026, 8, 10)), block(start: date(2026, 9, 7)),
                      block(start: date(2026, 9, 20), mode: .menopause)]
        let r = renderer(blocks: blocks)
        let predicted = r.predictedDays(month: october, today: date(2026, 10, 1))
        XCTAssertEqual(predicted.min(), date(2026, 10, 5), "28 days after September 7, not shaped by the menopause block")
        XCTAssertEqual(predicted.count, 5)
    }

    // MARK: - App icon

    /// The header logo is the real app icon (the `ExportLogo` image set, a copy of the 1024 px icon),
    /// drawn as an image with rounded corners. It is an image, so it adds no text to the page.
    func testExportLogoImageLoadsByName() throws {
        let image = try XCTUnwrap(PDFDrawing.appIconImage, "ExportLogo is in the asset catalog")
        XCTAssertGreaterThanOrEqual(image.size.width * image.scale, 512)
    }

    func testAppIconDrawsWithRoundedCorners() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format).image { ctx in
            XCTAssertTrue(PDFDrawing.drawAppIcon(in: ctx.cgContext, rect: CGRect(x: 0, y: 0, width: 40, height: 40)))
        }
        XCTAssertTrue(CalendarPDFTests.hasInk(image), "the icon draws visible ink")
        XCTAssertEqual(CalendarPDFTests.alpha(image, x: 0, y: 0), 0, "the corner is clipped away")
        XCTAssertEqual(CalendarPDFTests.alpha(image, x: 40, y: 40), 255, "the middle is solid icon art")
    }

    func testCalendarPageCarriesTheIconAsAnImage() throws {
        let data = renderer().render(month: october, paper: .letter, lightTints: false, today: today)
        XCTAssertTrue(CalendarPDFTests.containsImageXObject(data), "the page draws the app icon image")
        XCTAssertEqual(try document(data).pageCount, 1)
    }

    static func containsImageXObject(_ data: Data) -> Bool {
        data.range(of: Data("/Subtype /Image".utf8)) != nil
    }

    private static func alpha(_ image: UIImage, x: Int, y: Int) -> UInt8? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels[(min(y, height - 1) * width + min(x, width - 1)) * 4 + 3]
    }

    // MARK: - Review samples

    /// Writes Letter and A4, portrait and landscape samples of both PDFs for a human to look at. Runs only when the test runner has
    /// `RHYTHMX_PDF_SAMPLE_DIR` (pass it as `TEST_RUNNER_RHYTHMX_PDF_SAMPLE_DIR=<dir>` to xcodebuild).
    func testWritesSamplePDFsForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["RHYTHMX_PDF_SAMPLE_DIR"], !dir.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_RHYTHMX_PDF_SAMPLE_DIR to write review samples")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        func block(start: Date, length: Int, tags: String = "") -> ArchivedDataBlock {
            var events = CycleGenerator.events(startDate: start, cycleLength: length)
            if !tags.isEmpty { events[1].tags = tags }
            let grouped = Dictionary(grouping: events, by: { $0.eventType })
                .map { ArchivedDataBlock.PhaseEvents(eventType: $0.key, events: $0.value) }
            return ArchivedDataBlock(date: start, groupedEvents: grouped)
        }
        let blocks = [block(start: date(2026, 5, 3), length: 27, tags: "Symptom:Cramps, Symptom:Headache, Mood:Irritable"),
                      block(start: date(2026, 5, 30), length: 29, tags: "Symptom:Cramps, Symptom:Bloating"),
                      block(start: date(2026, 6, 28), length: 48, tags: "Symptom:Fatigue"),
                      block(start: date(2026, 8, 15), length: 28, tags: "Symptom:Cramps, Symptom:Back Pain")]
        var current = CycleGenerator.events(startDate: date(2026, 10, 3), cycleLength: 28)
        current[0].tags = "Symptom:Cramps"
        let calendarRenderer = CalendarPDFRenderer(events: current, archivedBlocks: blocks)
        let report = DoctorReportBuilder.make(events: current, archivedBlocks: blocks, mode: .cycle, today: today)
        let menopauseEvents = [Event(eventType: .menstrual, date: date(2026, 2, 14), note: "")] + (0..<40).map { offset in
            Event(eventType: .follicular, date: calendar.date(byAdding: .day, value: -offset, to: today)!, note: "",
                  tags: offset % 3 == 0 ? "Menopause:Hot Flashes, Menopause:Hot Flashes, Menopause:Poor Sleep" : "Menopause:Night Sweats",
                  mode: .menopause)
        }
        let menopause = DoctorReportBuilder.make(events: menopauseEvents, archivedBlocks: [], mode: .menopause, today: today)
        let sparse = DoctorReportBuilder.make(events: current, archivedBlocks: [blocks[0]], mode: .cycle, today: today)
        let reportRenderer = DoctorReportPDFRenderer(today: today)

        // A six-row month on a Monday-first calendar.
        var monday = Calendar(identifier: .gregorian)
        monday.firstWeekday = 2
        let august = monday.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let sixRows = CalendarPDFRenderer(events: CycleGenerator.events(startDate: date(2026, 8, 3), cycleLength: 28),
                                          archivedBlocks: [], calendar: monday)

        for paper in PaperSize.allCases {
            for orientation in PaperSize.Orientation.allCases {
                let name = "\(paper.rawValue)-\(orientation.rawValue)"
                try calendarRenderer.render(month: october, paper: paper, orientation: orientation, lightTints: false, today: today)
                    .write(to: folder.appendingPathComponent("calendar-\(name).pdf"))
                try calendarRenderer.render(month: october, paper: paper, orientation: orientation, lightTints: true, today: today)
                    .write(to: folder.appendingPathComponent("calendar-\(name)-light-tints.pdf"))
                try sixRows.render(month: august, paper: paper, orientation: orientation, lightTints: false, today: august)
                    .write(to: folder.appendingPathComponent("calendar-six-rows-monday-\(name).pdf"))
                try reportRenderer.render(report, paper: paper, orientation: orientation, name: "Jane Example", birthDate: date(1988, 4, 23))
                    .write(to: folder.appendingPathComponent("report-\(name).pdf"))
                try reportRenderer.render(menopause, paper: paper, orientation: orientation, name: nil, birthDate: nil)
                    .write(to: folder.appendingPathComponent("report-menopause-\(name).pdf"))
                try reportRenderer.render(sparse, paper: paper, orientation: orientation, name: nil, birthDate: nil)
                    .write(to: folder.appendingPathComponent("report-sparse-\(name).pdf"))
            }
        }
    }

    private static func hasInk(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
    }
}
