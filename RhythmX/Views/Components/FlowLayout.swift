//  FlowLayout.swift

import SwiftUI

/// Wraps children onto new lines when they run out of width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    private let tolerance: CGFloat = 0.5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if x + size.width > maxW + tolerance, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if x - bounds.minX + size.width > maxW + tolerance, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: maxW, height: nil))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
