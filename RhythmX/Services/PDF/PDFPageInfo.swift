//  PDFPageInfo.swift
//
//  Size information for the export preview: the paper's name and its real dimensions ("Letter, 8.5 x 11 in",
//  "A4, 210 x 297 mm"), the page size in PDF points, the aspect ratio the preview is drawn at, the page count
//  and a scale hint. Dimensions use inches where the region measures paper in inches (the US, Liberia and
//  Myanmar) and millimeters everywhere else. Pure values, so they are tested on their own.

import CoreGraphics
import Foundation

struct PDFPageInfo: Equatable {
    enum Unit: Equatable {
        case inches
        case millimeters
    }

    let paper: PaperSize
    let orientation: PaperSize.Orientation
    let unit: Unit

    init(paper: PaperSize, orientation: PaperSize.Orientation, unit: Unit) {
        self.paper = paper
        self.orientation = orientation
        self.unit = unit
    }

    init(paper: PaperSize, orientation: PaperSize.Orientation, locale: Locale = .current) {
        self.init(paper: paper, orientation: orientation, unit: Self.unit(for: locale))
    }

    /// Regions that measure paper in inches: the United States, Liberia and Myanmar.
    static let inchRegions: Set<String> = ["US", "LR", "MM"]

    static func unit(for locale: Locale) -> Unit {
        guard let region = locale.region?.identifier else { return .millimeters }
        return inchRegions.contains(region) ? .inches : .millimeters
    }

    /// Page size in PDF points (1/72 inch), as the renderers draw it.
    var pageSize: CGSize { paper.size(orientation) }

    /// Width over height, the ratio the preview is drawn at.
    var aspectRatio: CGFloat { pageSize.width / pageSize.height }

    /// Width and height of the sheet as printed, for example "8.5 x 11 in" or "297 x 210 mm".
    var dimensions: String {
        let (width, height): (Double, Double)
        switch unit {
        case .inches:
            (width, height) = paper.inches
            let swapped = orientation == .landscape
            return "\(Self.inchText(swapped ? height : width)) x \(Self.inchText(swapped ? width : height)) in"
        case .millimeters:
            (width, height) = paper.millimeters
            let swapped = orientation == .landscape
            return "\(Self.millimeterText(swapped ? height : width)) x \(Self.millimeterText(swapped ? width : height)) mm"
        }
    }

    /// "Letter, 8.5 x 11 in".
    var label: String { "\(paper.title), \(dimensions)" }

    /// "1 page", "2 pages".
    static func pageCountText(_ count: Int) -> String {
        count == 1 ? "1 page" : "\(count) pages"
    }

    /// The on-screen preview is always smaller than the page, and how much smaller depends on the iPhone
    /// model, so no percentage is shown. The sentence names the paper the file is sized for instead.
    var scaleHint: String { "Preview is reduced to fit. The PDF prints at full size on \(paper.title) paper." }

    /// One decimal at most, no trailing ".0": 8.5, 11, 8.3, 11.7.
    private static func inchText(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        return tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), tenths)
    }

    private static func millimeterText(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}

extension PaperSize {
    /// Portrait width and height in inches. Letter is defined in inches; A4 is converted from millimeters.
    var inches: (Double, Double) {
        switch self {
        case .letter: return (8.5, 11)
        case .a4:     return (210 / 25.4, 297 / 25.4)
        }
    }

    /// Portrait width and height in millimeters. A4 is defined in millimeters; Letter is converted from inches.
    var millimeters: (Double, Double) {
        switch self {
        case .letter: return (8.5 * 25.4, 11 * 25.4)
        case .a4:     return (210, 297)
        }
    }
}
