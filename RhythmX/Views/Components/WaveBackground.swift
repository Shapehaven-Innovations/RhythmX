//  WaveBackground.swift

import SwiftUI

struct WaveShape: Shape {
    var amplitude: CGFloat
    var wavelength: CGFloat
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        while x <= rect.maxX {
            let y = rect.minY + amplitude + amplitude * sin(2 * .pi * (x - rect.minX) / wavelength + phase)
            p.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Three layered waves filling its frame from the bottom. Drift is off by default.
struct WaveBackground: View {
    var drift: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !(drift && !reduceMotion))) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                layer(color: DS.Color.waveBack,  opacity: 0.35, top: 0.00, phase: t * 0.6)
                layer(color: DS.Color.waveMid,   opacity: 0.50, top: 0.22, phase: t * 0.9 + 1)
                layer(color: DS.Color.waveFront, opacity: 0.75, top: 0.46, phase: t * 1.2 + 2)
            }
        }
        .accessibilityHidden(true)
    }

    private func layer(color: Color, opacity: Double, top: CGFloat, phase: Double) -> some View {
        GeometryReader { geo in
            WaveShape(amplitude: 8, wavelength: max(geo.size.width * 0.6, 120), phase: CGFloat(phase))
                .fill(color.opacity(opacity))
                .frame(height: geo.size.height * (1 - top))
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

#Preview {
    WaveBackground(drift: true)
        .frame(height: 220)
        .background(DS.Color.pageBackground)
}
