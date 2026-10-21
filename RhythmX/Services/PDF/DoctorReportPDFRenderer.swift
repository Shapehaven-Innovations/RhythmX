//  DoctorReportPDFRenderer.swift
//
//  One page for the doctor: cycle and period averages, variation, a bar chart of the last cycles, the most
//  logged symptoms and the period start dates. Name and date of birth are arguments only; they are drawn
//  on the page and nowhere else. The page ends with "Tracking tool, not medical advice." Portrait is one
//  column; landscape is still one page, in two columns (statistics and symptoms on the left, the cycle chart
//  and period start dates on the right).

import UIKit

struct DoctorReportPDFRenderer {
    static let disclaimer = "Tracking tool, not medical advice."
    static let sparseMessage = "Log a few more cycles to see cycle statistics here. The report needs at least two completed cycles."
    static let menopauseSparseMessage = "Log a few entries in Menopause mode to see them here."

    var today: Date = Date()
    var calendar: Calendar = .current

    init(today: Date = Date(), calendar: Calendar = .current) {
        self.today = today
        self.calendar = calendar
    }

    // MARK: - Cycle report

    /// A report built in Menopause mode renders its variant.
    func render(_ report: DoctorReport, paper: PaperSize, orientation: PaperSize.Orientation = .portrait,
                name: String?, birthDate: Date?) -> Data {
        if let menopause = report.menopause {
            return renderMenopause(menopause, paper: paper, orientation: orientation, name: name, birthDate: birthDate)
        }
        let page = CGRect(origin: .zero, size: paper.size(orientation))
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: PDFDrawing.format(title: "Cycle Report"))
        return renderer.pdfData { context in
            context.beginPage()
            let cg = context.cgContext
            var y = header(cg, page: page, title: "Cycle Report", name: name, birthDate: birthDate)
            let margin = PDFDrawing.margin
            let width = page.width - 2 * margin

            if orientation == .landscape {
                landscapeColumns(cg, report: report, page: page, top: y)
                footer(cg, page: page)
                return
            }

            if report.hasEnoughData {
                y = statTiles(cg, y: y, width: width, tiles: [
                    ("Average cycle", days(report.averageCycle)),
                    ("Average period", days(report.averagePeriod)),
                    ("Variation", report.variation.map { "± \($0.formatted(.number.precision(.fractionLength(1)))) days" } ?? "-")
                ])
                y = sectionTitle("Cycle lengths, last \(report.cycleLengths.count)", y: y)
                y = cycleChart(cg, report: report, y: y, width: width)
            } else {
                y = sectionTitle("Cycle statistics", y: y)
                y = note(Self.sparseMessage, y: y, width: width)
            }

            y = sectionTitle("Most logged symptoms", y: y)
            if report.topSymptoms.isEmpty {
                y = note("No symptom tags logged yet.", y: y, width: width)
            } else {
                y = symptomRows(cg, report.topSymptoms, y: y, width: width)
            }

            y = sectionTitle("Period start dates", y: y)
            if report.periodStarts.isEmpty {
                y = note("No period logged yet.", y: y, width: width)
            } else {
                let shown = Array(report.periodStarts.suffix(24))
                let prefix = shown.count < report.periodStarts.count ? "Last \(shown.count) of \(report.periodStarts.count): " : ""
                let line = prefix + shown.map { $0.formatted(.dateTime.year().month(.abbreviated).day()) }.joined(separator: "   ")
                y += PDFDrawing.paragraph(line, in: CGRect(x: margin, y: y, width: width, height: page.maxY - y - 60),
                                          font: PDFDrawing.font(10)) + 6
            }

            footer(cg, page: page)
        }
    }

    // MARK: - Menopause variant

    func renderMenopause(_ report: MenopauseReport, paper: PaperSize, orientation: PaperSize.Orientation = .portrait,
                         name: String?, birthDate: Date?) -> Data {
        let page = CGRect(origin: .zero, size: paper.size(orientation))
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: PDFDrawing.format(title: "Menopause Report"))
        return renderer.pdfData { context in
            context.beginPage()
            let cg = context.cgContext
            var y = header(cg, page: page, title: "Menopause Report", name: name, birthDate: birthDate)
            let margin = PDFDrawing.margin
            let width = page.width - 2 * margin

            guard report.hasData else {
                y = sectionTitle("Menopause tracking", y: y)
                _ = note(Self.menopauseSparseMessage, y: y, width: width)
                footer(cg, page: page)
                return
            }

            let last = report.lastPeriod.map { $0.formatted(.dateTime.year().month(.abbreviated).day()) } ?? "Not logged"
            y = statTiles(cg, y: y, width: width, tiles: [
                ("Months since last period", "\(report.monthsSinceLastPeriod)"),
                ("Last period", last),
                ("This week", "\(report.hotFlashesPerWeek.last ?? 0) hot flashes")
            ])

            let series: [(String, [Int])] = [
                ("Hot flashes", report.hotFlashesPerWeek),
                ("Night sweats", report.nightSweatsPerWeek),
                ("Poor sleep", report.poorSleepPerWeek)
            ]
            y = sectionTitle("Per week, last \(MenopauseInsights.weeks) weeks, oldest first", y: y)
            for (title, values) in series {
                y = weeklyChart(cg, title: title, values: values, y: y, width: width)
            }

            footer(cg, page: page)
        }
    }

    // MARK: - Landscape

    /// Two columns under the header: statistics and symptoms on the left, the cycle chart and the period start
    /// dates on the right, with a thin rule between them.
    private func landscapeColumns(_ cg: CGContext, report: DoctorReport, page: CGRect, top: CGFloat) {
        let margin = PDFDrawing.margin
        let gutter: CGFloat = 28
        let columnWidth = (page.width - 2 * margin - gutter) / 2
        let left = margin
        let right = margin + columnWidth + gutter
        let bottom = page.maxY - margin - 28

        var leftY = top
        if report.hasEnoughData {
            leftY = statTiles(cg, x: left, y: leftY, width: columnWidth, tiles: [
                ("Average cycle", days(report.averageCycle)),
                ("Average period", days(report.averagePeriod)),
                ("Variation", report.variation.map { "± \($0.formatted(.number.precision(.fractionLength(1)))) days" } ?? "-")
            ])
        } else {
            leftY = sectionTitle("Cycle statistics", x: left, y: leftY)
            leftY = note(Self.sparseMessage, x: left, y: leftY, width: columnWidth)
        }
        leftY = sectionTitle("Most logged symptoms", x: left, y: leftY)
        if report.topSymptoms.isEmpty {
            leftY = note("No symptom tags logged yet.", x: left, y: leftY, width: columnWidth)
        } else {
            leftY = symptomRows(cg, report.topSymptoms, x: left, y: leftY, width: columnWidth)
        }

        var rightY = top
        if report.hasEnoughData {
            rightY = sectionTitle("Cycle lengths, last \(report.cycleLengths.count)", x: right, y: rightY)
            rightY = cycleChart(cg, report: report, x: right, y: rightY + 12, width: columnWidth,
                                chartHeight: 160, labelGutter: 44)
        }
        rightY = sectionTitle("Period start dates", x: right, y: rightY)
        if report.periodStarts.isEmpty {
            rightY = note("No period logged yet.", x: right, y: rightY, width: columnWidth)
        } else {
            let shown = Array(report.periodStarts.suffix(24))
            let prefix = shown.count < report.periodStarts.count ? "Last \(shown.count) of \(report.periodStarts.count): " : ""
            let line = prefix + shown.map { $0.formatted(.dateTime.year().month(.abbreviated).day()) }.joined(separator: "   ")
            rightY += PDFDrawing.paragraph(line, in: CGRect(x: right, y: rightY, width: columnWidth, height: max(0, bottom - rightY)),
                                           font: PDFDrawing.font(10)) + 6
        }

        let divider = margin + columnWidth + gutter / 2
        PDFDrawing.rule(cg, from: CGPoint(x: divider, y: top), to: CGPoint(x: divider, y: min(max(leftY, rightY), bottom)))
    }

    // MARK: - Pieces

    private func days(_ value: Double?) -> String {
        guard let value else { return "-" }
        let rounded = value.rounded()
        return abs(value - rounded) < 0.05 ? "\(Int(rounded)) days" : "\(value.formatted(.number.precision(.fractionLength(1)))) days"
    }

    /// Title, the app icon, the prepared date and the optional patient line. Returns the next free y.
    private func header(_ cg: CGContext, page: CGRect, title: String, name: String?, birthDate: Date?) -> CGFloat {
        let margin = PDFDrawing.margin
        let width = page.width - 2 * margin
        let logo: CGFloat = 30
        PDFDrawing.text(title, in: CGRect(x: margin, y: margin, width: width - logo - 12, height: 30),
                        font: PDFDrawing.font(22, weight: .bold))
        PDFDrawing.drawAppIcon(in: cg, rect: CGRect(x: page.maxX - margin - logo, y: margin - 2, width: logo, height: logo))
        PDFDrawing.text("Prepared \(today.formatted(.dateTime.year().month(.wide).day()))",
                        in: CGRect(x: margin, y: margin + 30, width: width - logo - 12, height: 14),
                        font: PDFDrawing.font(9.5), color: PDFDrawing.muted)
        var y = margin + 52

        var parts: [String] = []
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { parts.append("Name: \(name)") }
        if let birthDate { parts.append("Date of birth: \(birthDate.formatted(.dateTime.year().month(.abbreviated).day()))") }
        if !parts.isEmpty {
            PDFDrawing.text(parts.joined(separator: "      "), in: CGRect(x: margin, y: y, width: width, height: 16),
                            font: PDFDrawing.font(11, weight: .medium))
            y += 20
        }
        PDFDrawing.rule(cg, from: CGPoint(x: margin, y: y), to: CGPoint(x: page.maxX - margin, y: y))
        return y + 12
    }

    private func sectionTitle(_ title: String, x: CGFloat = PDFDrawing.margin, y: CGFloat) -> CGFloat {
        PDFDrawing.text(title, at: CGPoint(x: x, y: y), font: PDFDrawing.font(12, weight: .semibold))
        return y + 20
    }

    private func note(_ text: String, x: CGFloat = PDFDrawing.margin, y: CGFloat, width: CGFloat) -> CGFloat {
        let height = PDFDrawing.paragraph(text, in: CGRect(x: x, y: y, width: width, height: 60),
                                          font: PDFDrawing.font(10.5), color: PDFDrawing.muted)
        return y + height + 14
    }

    private func statTiles(_ cg: CGContext, x: CGFloat = PDFDrawing.margin, y: CGFloat, width: CGFloat,
                           tiles: [(String, String)]) -> CGFloat {
        let gap: CGFloat = 10
        let tileWidth = (width - gap * CGFloat(tiles.count - 1)) / CGFloat(tiles.count)
        let height: CGFloat = 54
        for (index, tile) in tiles.enumerated() {
            let frame = CGRect(x: x + CGFloat(index) * (tileWidth + gap), y: y, width: tileWidth, height: height)
            cg.setFillColor(PDFDrawing.faint.cgColor)
            cg.addPath(UIBezierPath(roundedRect: frame, cornerRadius: 8).cgPath)
            cg.fillPath()
            PDFDrawing.text(tile.0, in: CGRect(x: frame.minX + 10, y: frame.minY + 8, width: frame.width - 20, height: 13),
                            font: PDFDrawing.font(9), color: PDFDrawing.muted)
            PDFDrawing.text(tile.1, in: CGRect(x: frame.minX + 10, y: frame.minY + 24, width: frame.width - 20, height: 22),
                            font: PDFDrawing.font(16, weight: .semibold))
        }
        return y + height + 18
    }

    /// - Parameter labelGutter: room kept free of bars on the right for the threshold label (landscape, where
    ///   the narrower column would otherwise put the last bar under it).
    private func cycleChart(_ cg: CGContext, report: DoctorReport, x margin: CGFloat = PDFDrawing.margin,
                            y: CGFloat, width: CGFloat, chartHeight: CGFloat = 110, labelGutter: CGFloat = 0) -> CGFloat {
        let labelHeight: CGFloat = 26
        let baseline = y + chartHeight
        let maxValue = CGFloat(max(report.cycleLengths.max() ?? 0, DoctorReport.longCycleDays + 5))
        let slot = (width - labelGutter) / CGFloat(max(report.cycleLengths.count, 1))
        let barWidth = min(44, slot * 0.6)

        // Reference line at the long-cycle threshold.
        let longY = baseline - chartHeight * CGFloat(DoctorReport.longCycleDays) / maxValue
        cg.saveGState()
        cg.setStrokeColor(PDFDrawing.line.cgColor)
        cg.setLineWidth(0.5)
        cg.setLineDash(phase: 0, lengths: [3, 3])
        cg.move(to: CGPoint(x: margin, y: longY))
        cg.addLine(to: CGPoint(x: margin + width, y: longY))
        cg.strokePath()
        cg.restoreGState()
        PDFDrawing.text("\(DoctorReport.longCycleDays) days", at: CGPoint(x: margin + width - 40, y: longY - 12),
                        font: PDFDrawing.font(8), color: PDFDrawing.muted)

        for (index, length) in report.cycleLengths.enumerated() {
            let isLong = report.longCycleIndexes.contains(index)
            let barHeight = chartHeight * CGFloat(length) / maxValue
            let x = margin + CGFloat(index) * slot + (slot - barWidth) / 2
            let bar = CGRect(x: x, y: baseline - barHeight, width: barWidth, height: barHeight)
            cg.setFillColor((isLong ? PDFDrawing.accent.withAlphaComponent(0.55) : PDFDrawing.accent).cgColor)
            cg.addPath(UIBezierPath(roundedRect: bar, cornerRadius: 3).cgPath)
            cg.fillPath()
            PDFDrawing.text("\(length)", in: CGRect(x: x - 10, y: bar.minY - 14, width: barWidth + 20, height: 12),
                            font: PDFDrawing.font(9, weight: .semibold), alignment: .center)
            let start = index < report.cycleStarts.count
                ? report.cycleStarts[index].formatted(.dateTime.month(.abbreviated).day()) : ""
            PDFDrawing.text(start, in: CGRect(x: x - 14, y: baseline + 4, width: barWidth + 28, height: 12),
                            font: PDFDrawing.font(8.5), color: PDFDrawing.muted, alignment: .center)
            if isLong {
                PDFDrawing.text("long", in: CGRect(x: x - 14, y: baseline + 15, width: barWidth + 28, height: 11),
                                font: PDFDrawing.font(8, weight: .semibold), color: PDFDrawing.accent, alignment: .center)
            }
        }
        PDFDrawing.rule(cg, from: CGPoint(x: margin, y: baseline), to: CGPoint(x: margin + width, y: baseline), color: PDFDrawing.muted)
        return baseline + labelHeight + 14
    }

    private func symptomRows(_ cg: CGContext, _ symptoms: [SymptomCount], x margin: CGFloat = PDFDrawing.margin,
                             y: CGFloat, width: CGFloat) -> CGFloat {
        let rowHeight: CGFloat = 16
        let maxCount = CGFloat(symptoms.map(\.count).max() ?? 1)
        let barX = margin + 150
        let barWidth = width - 150 - 40
        var y = y
        for symptom in symptoms {
            PDFDrawing.text(symptom.label, in: CGRect(x: margin, y: y, width: 140, height: rowHeight), font: PDFDrawing.font(10))
            let bar = CGRect(x: barX, y: y + 4, width: max(2, barWidth * CGFloat(symptom.count) / maxCount), height: 8)
            cg.setFillColor(PDFDrawing.accent.withAlphaComponent(0.7).cgColor)
            cg.addPath(UIBezierPath(roundedRect: bar, cornerRadius: 2).cgPath)
            cg.fillPath()
            PDFDrawing.text("\(symptom.count)", in: CGRect(x: barX + barWidth + 6, y: y, width: 34, height: rowHeight),
                            font: PDFDrawing.font(10, weight: .semibold))
            y += rowHeight
        }
        return y + 12
    }

    private func weeklyChart(_ cg: CGContext, title: String, values: [Int], y: CGFloat, width: CGFloat) -> CGFloat {
        let margin = PDFDrawing.margin
        let chartHeight: CGFloat = 54
        PDFDrawing.text(title, at: CGPoint(x: margin, y: y), font: PDFDrawing.font(10.5, weight: .medium))
        let top = y + 16
        let baseline = top + chartHeight
        let maxValue = CGFloat(max(values.max() ?? 0, 1))
        let slot = width / CGFloat(max(values.count, 1))
        let barWidth = min(30, slot * 0.5)
        for (index, value) in values.enumerated() {
            let x = margin + CGFloat(index) * slot + (slot - barWidth) / 2
            let barHeight = chartHeight * CGFloat(value) / maxValue
            if value > 0 {
                let bar = CGRect(x: x, y: baseline - barHeight, width: barWidth, height: barHeight)
                cg.setFillColor(PDFDrawing.accent.withAlphaComponent(0.75).cgColor)
                cg.addPath(UIBezierPath(roundedRect: bar, cornerRadius: 2).cgPath)
                cg.fillPath()
            }
            PDFDrawing.text("\(value)", in: CGRect(x: x - 10, y: baseline - barHeight - 12, width: barWidth + 20, height: 11),
                            font: PDFDrawing.font(8.5), color: value > 0 ? PDFDrawing.ink : PDFDrawing.muted, alignment: .center)
            let weeksAgo = values.count - 1 - index
            PDFDrawing.text(weeksAgo == 0 ? "This week" : "\(weeksAgo) wk ago",
                            in: CGRect(x: x - 16, y: baseline + 3, width: barWidth + 32, height: 10),
                            font: PDFDrawing.font(7.5), color: PDFDrawing.muted, alignment: .center)
        }
        PDFDrawing.rule(cg, from: CGPoint(x: margin, y: baseline), to: CGPoint(x: margin + width, y: baseline), color: PDFDrawing.muted)
        return baseline + 26
    }

    /// The disclaimer, drawn last so it is the last line of the page.
    private func footer(_ cg: CGContext, page: CGRect) {
        let margin = PDFDrawing.margin
        PDFDrawing.rule(cg, from: CGPoint(x: margin, y: page.maxY - margin - 20), to: CGPoint(x: page.maxX - margin, y: page.maxY - margin - 20))
        PDFDrawing.text(Self.disclaimer, in: CGRect(x: margin, y: page.maxY - margin - 14, width: page.width - 2 * margin, height: 14),
                        font: PDFDrawing.font(9), color: PDFDrawing.muted)
    }
}
