//  PhaseStrip.swift

import SwiftUI

/// Proportional four-segment bar. Segments with a zero count are skipped.
struct PhaseStrip: View {
    let segments: [(phase: Event.EventType, count: Int)]
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.count }, 1)
            HStack(spacing: 2) {
                ForEach(segments.filter { $0.count > 0 }, id: \.phase) { seg in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(appSettings.phaseColor(for: seg.phase))
                        .frame(width: max(2, (geo.size.width - 6) * CGFloat(seg.count) / CGFloat(total)))
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
