//  CalendarPDFRenderer.swift
//
//  The printable monthly calendar: one page, drawn on the device with UIGraphicsPDFRenderer. Day cells are
//  tinted by phase with the fixed phase colors, each day carries its moon glyph, period and fertile days are
//  marked, predicted period days get a dashed outline, and the page carries the app icon as an image. The page
//  never shows the app's name as text. The PDF is always light; the app theme does not reach it.
//
//  Cycle data only: menopause events and blocks are dropped here as well, whatever the caller passes in, so
//  the printout can never show a menopause entry as a cycle phase.

import SwiftUI
import UIKit

// MARK: - Paper

enum PaperSize: String, CaseIterable, Identifiable {
    case letter
    case a4

    var id: String { rawValue }

    /// US Letter in the US, A4 everywhere else.
    static var `default`: PaperSize { `default`(for: .current) }

    static func `default`(for locale: Locale) -> PaperSize {
        locale.region?.identifier == "US" ? .letter : .a4
    }

    enum Orientation: String, CaseIterable, Identifiable {
        case portrait
        case landscape

        var id: String { rawValue }

        var title: String {
            switch self {
            case .portrait:  return "Portrait"
            case .landscape: return "Landscape"
            }
        }
    }

    /// Portrait size in points (1/72 inch): Letter is 8.5 x 11 in, A4 is 210 x 297 mm.
    var size: CGSize {
        switch self {
        case .letter: return CGSize(width: 612, height: 792)
        case .a4:     return CGSize(width: 595, height: 842)
        }
    }

    /// Size in points for `orientation`; landscape swaps width and height.
    func size(_ orientation: Orientation) -> CGSize {
        orientation == .portrait ? size : CGSize(width: size.height, height: size.width)
    }

    var title: String {
        switch self {
        case .letter: return "Letter"
        case .a4:     return "A4"
        }
    }
}

// MARK: - Shared drawing

/// Ink, type and helpers shared by the calendar and the Doctor Report. The pages are always light.
enum PDFDrawing {
    static let ink = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    static let muted = UIColor(red: 0.43, green: 0.43, blue: 0.45, alpha: 1)
    static let line = UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1)
    static let faint = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    /// The brand accent of the light theme; today's outline and the report charts use it.
    static let accent = UIColor(red: 94 / 255, green: 38 / 255, blue: 79 / 255, alpha: 1)

    static let margin: CGFloat = 36

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    /// The light appearance of a SwiftUI color, so an adaptive phase color prints as its light variant.
    static func lightColor(_ color: Color) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }

    static func attributes(_ font: UIFont, color: UIColor = ink, alignment: NSTextAlignment = .left,
                           lineBreak: NSLineBreakMode = .byTruncatingTail) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreak
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    @discardableResult
    static func text(_ string: String, at point: CGPoint, font: UIFont, color: UIColor = ink) -> CGSize {
        let attributed = NSAttributedString(string: string, attributes: attributes(font, color: color))
        attributed.draw(at: point)
        return attributed.size()
    }

    /// Draws a single line into `rect`, truncating at the end. Returns the width the text used.
    @discardableResult
    static func text(_ string: String, in rect: CGRect, font: UIFont, color: UIColor = ink,
                     alignment: NSTextAlignment = .left) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: attributes(font, color: color, alignment: alignment))
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        return min(attributed.size().width, rect.width)
    }

    /// Multi-line paragraph, wrapped at word boundaries. Returns the height used.
    @discardableResult
    static func paragraph(_ string: String, in rect: CGRect, font: UIFont, color: UIColor = ink) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: attributes(font, color: color, lineBreak: .byWordWrapping))
        let bounds = attributed.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin], context: nil)
        attributed.draw(with: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(ceil(bounds.height), rect.height)),
                        options: [.usesLineFragmentOrigin], context: nil)
        return ceil(bounds.height)
    }

    // MARK: App icon

    /// The real app icon, from the `ExportLogo` image set (a copy of the 1024 px App Icon, since an app icon
    /// set cannot be loaded by name). The art carries no text, so the calendar stays free of the app name.
    static var appIconImage: UIImage? { UIImage(named: "ExportLogo") }

    /// The icon scaled down once to a size that prints sharply at the header size, so each PDF embeds a small
    /// image instead of the full 1024 px file.
    private static let appIconThumbnail: UIImage? = {
        guard let image = appIconImage else { return nil }
        let side: CGFloat = 192
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }()

    /// Draws the app icon into `rect`, clipped to the iOS icon's rounded corners. Returns false, and draws
    /// nothing, when the image cannot be loaded.
    @discardableResult
    static func drawAppIcon(in context: CGContext, rect: CGRect) -> Bool {
        guard let icon = appIconThumbnail else { return false }
        context.saveGState()
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.2237).cgPath)
        context.clip()
        UIGraphicsPushContext(context)
        icon.draw(in: rect)
        UIGraphicsPopContext()
        context.restoreGState()
        return true
    }

    static func rule(_ context: CGContext, from: CGPoint, to: CGPoint, color: UIColor = line, width: CGFloat = 0.5) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
        context.restoreGState()
    }

    /// A moon glyph with the same shapes as `MoonPhaseView`, drawn with Core Graphics.
    static func moon(_ phase: MoonPhase, in context: CGContext, rect: CGRect, color: UIColor) {
        let size = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size)
        context.saveGState()
        switch phase {
        case .new:
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(max(1, size / 14))
            context.strokeEllipse(in: square.insetBy(dx: 1, dy: 1))
        case .full:
            context.setFillColor(color.withAlphaComponent(0.25).cgColor)
            context.fillEllipse(in: square)
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: scaled(square, 0.72))
        case .crescent, .waning:
            let disc = scaled(square, 0.82)
            let dx = (phase == .crescent ? 1 : -1) * size * 0.225
            let bite = disc.offsetBy(dx: dx, dy: -size * 0.04)
            context.addEllipse(in: disc)
            context.clip()
            context.setFillColor(color.cgColor)
            let path = CGMutablePath()
            path.addEllipse(in: disc)
            path.addEllipse(in: bite)
            context.addPath(path)
            context.fillPath(using: .evenOdd)
        }
        context.restoreGState()
    }

    static func scaled(_ rect: CGRect, _ factor: CGFloat) -> CGRect {
        let w = rect.width * factor, h = rect.height * factor
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    static func format(title: String) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: title
        ]
        return format
    }
}

// MARK: - Calendar

struct CalendarPDFRenderer {
    static let tintAlpha: CGFloat = 0.30
    static let lightTintAlpha: CGFloat = 0.18
    static let predictedLength = 5

    let events: [Event]
    let archivedBlocks: [ArchivedDataBlock]
    let colors: [Event.EventType: UIColor]
    let fertileOverrides: FertileOverrides
    let calendar: Calendar

    /// The page always uses the fixed phase colors, in their light variant.
    init(events: [Event], archivedBlocks: [ArchivedDataBlock],
         fertileOverrides: FertileOverrides = FertileOverrides(), calendar: Calendar = .current) {
        self.events = events.filter { $0.effectiveMode != .menopause }
        self.archivedBlocks = archivedBlocks.filter { $0.effectiveMode != .menopause }
        var map: [Event.EventType: UIColor] = [:]
        for phase in Event.EventType.allCases {
            map[phase] = PDFDrawing.lightColor(phase.defaultPhaseColor)
        }
        self.colors = map
        self.fertileOverrides = fertileOverrides
        self.calendar = calendar
    }

    // MARK: Data behind the page (tested on their own)

    /// Start-of-day to logged phase for the days of `month`.
    func tintedDays(month: Date) -> [Date: Event.EventType] {
        var result: [Date: Event.EventType] = [:]
        for cell in CalendarMonthModel(containing: month, calendar: calendar).cells {
            guard let day = cell, let phase = CalendarPhaseLookup.phase(on: day.date, events: events, calendar: calendar) else { continue }
            result[calendar.startOfDay(for: day.date)] = phase
        }
        return result
    }

    /// Fertile day keys (`FertileWindow.dayKey`) for the whole data set; the page checks the month's days against it.
    func fertileDays(month: Date) -> Set<String> {
        FertileWindow.days(events: events, overrides: fertileOverrides, calendar: calendar)
    }

    /// Predicted period days of `month`: the Calendar tab's rule (no logged phase, not in the past).
    func predictedDays(month: Date, today: Date) -> Set<Date> {
        let start = InsightsViewModel(events: events, archivedBlocks: archivedBlocks, appSettings: AppSettings())
            .cycleStats(today: today).nextPeriodEstimate
        guard start != nil else { return [] }
        let tinted = tintedDays(month: month)
        let todayStart = calendar.startOfDay(for: today)
        var result = Set<Date>()
        for cell in CalendarMonthModel(containing: month, calendar: calendar).cells {
            guard let day = cell else { continue }
            let date = calendar.startOfDay(for: day.date)
            guard tinted[date] == nil, date >= todayStart,
                  CalendarPhaseLookup.isPredictedPeriod(date, start: start, length: Self.predictedLength, calendar: calendar)
            else { continue }
            result.insert(date)
        }
        return result
    }

    // MARK: Page

    /// Landscape uses the same layout on a wider, shorter page: the cells get wide and short so a six-row
    /// month still fits above the legend and footer.
    func render(month: Date, paper: PaperSize, orientation: PaperSize.Orientation = .portrait,
                lightTints: Bool, today: Date = Date()) -> Data {
        let model = CalendarMonthModel(containing: month, calendar: calendar)
        let page = CGRect(origin: .zero, size: paper.size(orientation))
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: PDFDrawing.format(title: "Calendar \(model.title)"))
        let tinted = tintedDays(month: month)
        let fertile = fertileDays(month: month)
        let predicted = predictedDays(month: month, today: today)
        let alpha = lightTints ? Self.lightTintAlpha : Self.tintAlpha
        let todayStart = calendar.startOfDay(for: today)

        return renderer.pdfData { context in
            context.beginPage()
            let cg = context.cgContext
            let margin = PDFDrawing.margin
            let contentWidth = page.width - 2 * margin

            // Header: month title on the left, the app icon on the right. No app name in the text.
            let logoSize: CGFloat = 30
            PDFDrawing.text(model.title, in: CGRect(x: margin, y: margin, width: contentWidth - logoSize - 12, height: 30),
                            font: PDFDrawing.font(22, weight: .bold))
            PDFDrawing.drawAppIcon(in: cg, rect: CGRect(x: page.maxX - margin - logoSize, y: margin - 2, width: logoSize, height: logoSize))
            PDFDrawing.text("Phase calendar with logged and predicted days",
                            in: CGRect(x: margin, y: margin + 30, width: contentWidth - logoSize - 12, height: 14),
                            font: PDFDrawing.font(9.5), color: PDFDrawing.muted)

            // Weekday header.
            let gridTop = margin + 58
            let columnWidth = contentWidth / 7
            for (index, symbol) in model.weekdaySymbols.enumerated() {
                PDFDrawing.text(symbol, in: CGRect(x: margin + CGFloat(index) * columnWidth, y: gridTop, width: columnWidth, height: 14),
                                font: PDFDrawing.font(9, weight: .semibold), color: PDFDrawing.muted, alignment: .center)
            }
            PDFDrawing.rule(cg, from: CGPoint(x: margin, y: gridTop + 17), to: CGPoint(x: page.maxX - margin, y: gridTop + 17))

            // Grid.
            let legendHeight: CGFloat = 58
            let footerHeight: CGFloat = 16
            let cells = model.cells
            let rows = max(1, cells.count / 7)
            let available = page.height - (gridTop + 22) - legendHeight - footerHeight - margin
            let rowHeight = min(available / CGFloat(rows), columnWidth * 1.35)
            let gridOrigin = CGPoint(x: margin, y: gridTop + 22)
            let gap: CGFloat = 3

            for (index, cell) in cells.enumerated() {
                guard let day = cell else { continue }
                let column = index % 7, row = index / 7
                let frame = CGRect(x: gridOrigin.x + CGFloat(column) * columnWidth + gap / 2,
                                   y: gridOrigin.y + CGFloat(row) * rowHeight + gap / 2,
                                   width: columnWidth - gap, height: rowHeight - gap)
                let date = calendar.startOfDay(for: day.date)
                let phase = tinted[date]
                let color = phase.map { colors[$0] ?? $0.defaultPhaseColor.uiLight } ?? PDFDrawing.line
                let isToday = date == todayStart
                let path = UIBezierPath(roundedRect: frame, cornerRadius: 5)

                if let phase, let tint = colors[phase] {
                    cg.setFillColor(tint.withAlphaComponent(alpha).cgColor)
                    cg.addPath(path.cgPath)
                    cg.fillPath()
                }
                cg.saveGState()
                cg.setStrokeColor((isToday ? PDFDrawing.accent : PDFDrawing.line).cgColor)
                cg.setLineWidth(isToday ? 1.5 : 0.5)
                cg.addPath(path.cgPath)
                cg.strokePath()
                cg.restoreGState()

                if predicted.contains(date) {
                    cg.saveGState()
                    cg.setStrokeColor((colors[.menstrual] ?? PDFDrawing.accent).cgColor)
                    cg.setLineWidth(1)
                    cg.setLineDash(phase: 0, lengths: [3, 2])
                    cg.addPath(UIBezierPath(roundedRect: frame.insetBy(dx: 2, dy: 2), cornerRadius: 4).cgPath)
                    cg.strokePath()
                    cg.restoreGState()
                }

                PDFDrawing.text("\(day.number)", at: CGPoint(x: frame.minX + 5, y: frame.minY + 3),
                                font: PDFDrawing.font(10.5, weight: isToday ? .bold : .regular),
                                color: isToday ? PDFDrawing.accent : PDFDrawing.ink)

                if let phase {
                    let glyph: CGFloat = min(11, frame.height * 0.3)
                    PDFDrawing.moon(phase.moonPhase, in: cg,
                                    rect: CGRect(x: frame.maxX - glyph - 5, y: frame.minY + 4, width: glyph, height: glyph),
                                    color: color)
                }

                // Marks along the bottom: period bar in the menstrual color, fertile capsule in the ovulation color.
                let markWidth = frame.width * 0.4
                var markX = frame.minX + 5
                if phase == .menstrual {
                    cg.setFillColor((colors[.menstrual] ?? color).cgColor)
                    cg.addPath(UIBezierPath(roundedRect: CGRect(x: markX, y: frame.maxY - 7, width: markWidth, height: 3), cornerRadius: 1.5).cgPath)
                    cg.fillPath()
                    markX += markWidth + 4
                }
                if fertile.contains(FertileWindow.dayKey(date, calendar: calendar)) {
                    cg.setFillColor((colors[.ovulation] ?? color).cgColor)
                    cg.addPath(UIBezierPath(roundedRect: CGRect(x: markX, y: frame.maxY - 7, width: markWidth, height: 3), cornerRadius: 1.5).cgPath)
                    cg.fillPath()
                }
            }

            // Legend.
            let legendTop = gridOrigin.y + CGFloat(rows) * rowHeight + 14
            drawLegend(cg, at: CGPoint(x: margin, y: legendTop), width: contentWidth)

            // Footer.
            PDFDrawing.text("Predictions are estimates and are not birth control.",
                            in: CGRect(x: margin, y: page.maxY - margin - footerHeight + 2, width: contentWidth, height: footerHeight),
                            font: PDFDrawing.font(8), color: PDFDrawing.muted)
        }
    }

    private func drawLegend(_ cg: CGContext, at origin: CGPoint, width: CGFloat) {
        let font = PDFDrawing.font(9)
        let swatch: CGFloat = 11
        var x = origin.x
        var y = origin.y
        let rowStep: CGFloat = 18

        func advance(by itemWidth: CGFloat) {
            if x + itemWidth > origin.x + width { x = origin.x; y += rowStep }
        }

        for phase in Event.EventType.allCases {
            let name = phase.rawValue.capitalized
            let textWidth = NSAttributedString(string: name, attributes: PDFDrawing.attributes(font)).size().width
            advance(by: swatch + 4 + textWidth + 14)
            PDFDrawing.moon(phase.moonPhase, in: cg, rect: CGRect(x: x, y: y + 1, width: swatch, height: swatch),
                            color: colors[phase] ?? phase.defaultPhaseColor.uiLight)
            PDFDrawing.text(name, at: CGPoint(x: x + swatch + 4, y: y), font: font)
            x += swatch + 4 + textWidth + 14
        }

        let items: [(String, (CGRect) -> Void)] = [
            ("Period", { rect in
                cg.setFillColor((colors[.menstrual] ?? PDFDrawing.ink).cgColor)
                cg.addPath(UIBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.midY - 1.5, width: rect.width, height: 3), cornerRadius: 1.5).cgPath)
                cg.fillPath()
            }),
            ("Fertile window", { rect in
                cg.setFillColor((colors[.ovulation] ?? PDFDrawing.ink).cgColor)
                cg.addPath(UIBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.midY - 1.5, width: rect.width, height: 3), cornerRadius: 1.5).cgPath)
                cg.fillPath()
            }),
            ("Predicted period", { rect in
                cg.saveGState()
                cg.setStrokeColor((colors[.menstrual] ?? PDFDrawing.ink).cgColor)
                cg.setLineWidth(1)
                cg.setLineDash(phase: 0, lengths: [3, 2])
                cg.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3).cgPath)
                cg.strokePath()
                cg.restoreGState()
            }),
            ("Today", { rect in
                cg.saveGState()
                cg.setStrokeColor(PDFDrawing.accent.cgColor)
                cg.setLineWidth(1.5)
                cg.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 3).cgPath)
                cg.strokePath()
                cg.restoreGState()
            })
        ]
        for (name, draw) in items {
            let textWidth = NSAttributedString(string: name, attributes: PDFDrawing.attributes(font)).size().width
            let swatchWidth: CGFloat = 14
            advance(by: swatchWidth + 4 + textWidth + 14)
            draw(CGRect(x: x, y: y + 1, width: swatchWidth, height: swatch))
            PDFDrawing.text(name, at: CGPoint(x: x + swatchWidth + 4, y: y), font: font)
            x += swatchWidth + 4 + textWidth + 14
        }
    }
}

private extension Color {
    var uiLight: UIColor { PDFDrawing.lightColor(self) }
}
