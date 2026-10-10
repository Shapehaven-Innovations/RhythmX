//  MoonPhaseView.swift

import SwiftUI

enum MoonPhase { case new, crescent, full, waning }

extension Event.EventType {
    var moonPhase: MoonPhase {
        switch self {
        case .menstrual:  return .full
        case .follicular: return .crescent
        case .ovulation:  return .new
        case .luteal:     return .waning
        }
    }
}

struct MoonPhaseView: View {
    let phase: MoonPhase
    var color: Color
    var isActive: Bool = false
    var size: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ZStack {
            if isActive {
                Circle().fill(color.opacity(breathing ? 0.30 : 0.18))
                    .scaleEffect(breathing ? 1.45 : 1.3)
            }
            switch phase {
            case .new:
                Circle().stroke(color, lineWidth: max(1.5, size / 14)).padding(1)
            case .full:
                ZStack {
                    Circle().fill(color.opacity(0.25))
                    Circle().fill(color).scaleEffect(0.72)
                }
            case .crescent, .waning:
                let dx = (phase == .crescent ? 1 : -1) * size * 0.225
                Circle()
                    .fill(color)
                    .scaleEffect(0.82)
                    .mask(
                        ZStack {
                            Rectangle()
                            Circle()
                                .scaleEffect(0.82)
                                .offset(x: dx, y: -size * 0.04)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(Event.EventType.allCases) { p in
            MoonPhaseView(phase: p.moonPhase, color: p.defaultPhaseColor, isActive: p == .ovulation, size: 40)
        }
    }
    .padding()
    .background(DS.Color.pageBackground)
}
