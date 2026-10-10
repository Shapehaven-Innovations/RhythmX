//  PhaseRingView.swift

import SwiftUI

struct PhaseRingView: View {
    let cycleLength: Int
    let currentPhase: Event.EventType?
    var lineWidth: CGFloat = 8
    @EnvironmentObject var appSettings: AppSettings

    private struct Arc { let phase: Event.EventType; let start: Double; let end: Double }

    private var arcs: [Arc] {
        let counts = CycleGenerator.dayCounts(cycleLength: cycleLength)
        let total = Double(max(counts.values.reduce(0, +), 1))
        var cursor = 0.0
        return Event.EventType.allCases.map { phase in
            let span = Double(counts[phase] ?? 0) / total
            defer { cursor += span }
            return Arc(phase: phase, start: cursor, end: cursor + span)
        }
    }

    var body: some View {
        ZStack {
            ForEach(arcs, id: \.phase) { arc in
                Circle()
                    .trim(from: arc.start + 0.006, to: max(arc.start + 0.006, arc.end - 0.006))
                    .stroke(appSettings.phaseColor(for: arc.phase),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
            }
            MoonPhaseView(
                phase: (currentPhase ?? .ovulation).moonPhase,
                color: currentPhase.map { appSettings.phaseColor(for: $0) } ?? DS.Color.tertiaryText,
                isActive: currentPhase != nil,
                size: 28
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(currentPhase.map { "Current phase: \($0.displayName)" } ?? "No active cycle")
    }
}
