//  MoonLogoMark.swift
//
//  The moon mark from the launch art (`LaunchMoons`) as vector: a soft halo, a ring and a crescent inside it.
//  The same paths draw the SwiftUI view and the PDF printout, so the mark is identical at every size.
//  It carries no app name; the printable calendar relies on that.

import SwiftUI
import UIKit

struct MoonLogoMark: View {
    var color: Color = DS.Color.accent
    var size: CGFloat = 28

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            context.fill(Path(Self.haloPath(in: rect)), with: .color(color.opacity(0.22)))
            context.stroke(Path(Self.ringPath(in: rect)), with: .color(color), lineWidth: Self.ringWidth(for: rect))
            var crescent = context
            crescent.clip(to: Path(Self.innerDisc(in: rect)))
            crescent.fill(Path(Self.crescentPath(in: rect)), with: .color(color), style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Geometry (shared by the view and the PDF)

    static func ringWidth(for rect: CGRect) -> CGFloat { max(1, min(rect.width, rect.height) / 18) }

    /// Light disc behind the ring, as on the launch screen's new moon.
    static func haloPath(in rect: CGRect) -> CGPath {
        CGPath(ellipseIn: rect.insetBy(dx: rect.width * 0.02, dy: rect.height * 0.02), transform: nil)
    }

    static func ringPath(in rect: CGRect) -> CGPath {
        let inset = rect.width * 0.17
        return CGPath(ellipseIn: rect.insetBy(dx: inset, dy: inset), transform: nil)
    }

    static func innerDisc(in rect: CGRect) -> CGRect {
        let inset = rect.width * 0.30
        return rect.insetBy(dx: inset, dy: inset)
    }

    /// A waxing crescent inside the ring: the inner disc minus a disc shifted to the left. Even-odd filled
    /// inside a clip to the inner disc, so only the crescent is left.
    static func crescentPath(in rect: CGRect) -> CGPath {
        let disc = innerDisc(in: rect)
        let bite = disc.offsetBy(dx: -disc.width * 0.32, dy: -disc.height * 0.04)
        let path = CGMutablePath()
        path.addEllipse(in: disc)
        path.addEllipse(in: bite)
        return path
    }

    /// Draws the mark into a Core Graphics context (UIKit orientation). Used by the PDF renderers.
    static func draw(in context: CGContext, rect: CGRect, color: UIColor) {
        context.saveGState()
        context.setFillColor(color.withAlphaComponent(0.22).cgColor)
        context.addPath(haloPath(in: rect))
        context.fillPath()

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(ringWidth(for: rect))
        context.addPath(ringPath(in: rect))
        context.strokePath()

        // Crescent: clip to the inner disc, then even-odd fill disc + bite leaves disc minus bite.
        context.saveGState()
        context.addEllipse(in: innerDisc(in: rect))
        context.clip()
        context.setFillColor(color.cgColor)
        context.addPath(crescentPath(in: rect))
        context.fillPath(using: .evenOdd)
        context.restoreGState()
        context.restoreGState()
    }
}

#Preview {
    HStack(spacing: 24) {
        MoonLogoMark(size: 20)
        MoonLogoMark(size: 40)
        MoonLogoMark(color: DS.Color.phase4Default, size: 80)
    }
    .padding()
    .background(DS.Color.pageBackground)
}
