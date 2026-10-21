//  TagSheetComponents.swift
//
//  The pieces of the Add Tags sheet and the quick log card: the moon strength glyph and its three-step
//  control (crescent light, half medium, full heavy), the ovulation test strip glyph, the count stepper,
//  the capsule chip, the round mood button and the tray chip.

import SwiftUI

// MARK: - Moon strength glyph

/// The lit part of a moon disc, lit from the right. `fraction` 0.5 is full, 0.25 half, about 0.13 a crescent.
struct LitMoonShape: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let k = cos(2 * .pi * min(max(fraction, 0), 0.5))   // terminator: 1 = nothing lit, -1 = full disc
        let steps = 28
        var path = Path()
        for i in 0...steps {   // right limb, top to bottom
            let t = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            let p = CGPoint(x: c.x + r * cos(t), y: c.y + r * sin(t))
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        for i in 0...steps {   // terminator, bottom to top
            let t = Double.pi / 2 - Double.pi * Double(i) / Double(steps)
            path.addLine(to: CGPoint(x: c.x + k * r * cos(t), y: c.y + r * sin(t)))
        }
        path.closeSubpath()
        return path
    }
}

/// The moon that stands for a strength: crescent for light, half for medium, full for heavy.
struct IntensityMoonGlyph: View {
    let level: TagIntensity
    var size: CGFloat = 16
    var lit: Color = DS.Color.accent
    var dim: Color = DS.Color.accent.opacity(0.18)

    static func fraction(_ level: TagIntensity) -> Double {
        switch level {
        case .light:  return 0.13
        case .medium: return 0.25
        case .heavy:  return 0.5
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(dim)
            LitMoonShape(fraction: Self.fraction(level)).fill(lit)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Three-step moon control

/// Light, medium and heavy as three moons in a track. A tap sets that level; a tap on the level already set
/// clears it (`TagFormLogic.tappedIntensity`). VoiceOver reads it as one adjustable control: "Cramps, Heavy".
struct MoonIntensityControl: View {
    let label: String
    let level: TagIntensity?
    let onChange: (TagIntensity?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionSpace

    static let segmentWidth: CGFloat = 50

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TagIntensity.allCases) { step in segment(step) }
        }
        .padding(2)
        .background(Capsule().fill(DS.Color.primaryText.opacity(0.06)))
        .sensoryFeedback(.selection, trigger: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(TagFormLogic.intensityValue(level))
        .accessibilityHint("Swipe up or down to set how strong it was")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(TagFormLogic.adjusted(level, up: true))
            case .decrement: onChange(TagFormLogic.adjusted(level, up: false))
            @unknown default: break
            }
        }
    }

    private func segment(_ step: TagIntensity) -> some View {
        let isOn = level == step
        let size: CGFloat = [13, 17, 21][step.rawValue - 1]
        return Button {
            let next = TagFormLogic.tappedIntensity(current: level, tapped: step)
            if reduceMotion { onChange(next) } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { onChange(next) }
            }
        } label: {
            IntensityMoonGlyph(level: step, size: size,
                               lit: isOn ? DS.Color.accent : DS.Color.secondaryText.opacity(0.55),
                               dim: isOn ? DS.Color.accent.opacity(0.2) : DS.Color.secondaryText.opacity(0.18))
                .scaleEffect(isOn && !reduceMotion ? 1.08 : 1)
                .frame(width: Self.segmentWidth, height: Self.segmentHeight)
                .background {
                    if isOn {
                        Capsule()
                            .fill(DS.Color.cardBackground)
                            .overlay(Capsule().strokeBorder(DS.Color.accent.opacity(0.55), lineWidth: 1.5))
                            .shadow(color: CardSurface.shadow, radius: 4, x: 0, y: 2)
                            .matchedGeometryEffect(id: "on", in: selectionSpace)
                    }
                }
                // A 44 pt tall hit area around the 34 pt moon; the extra 5 pt above and below take no layout
                // space, so the control looks the same.
                .padding(.vertical, Self.hitPadding)
                .contentShape(Rectangle())
                .padding(.vertical, -Self.hitPadding)
        }
        .buttonStyle(.plain)
    }

    static let segmentHeight: CGFloat = 34
    static let hitHeight: CGFloat = 44
    static var hitPadding: CGFloat { (hitHeight - segmentHeight) / 2 }
}

/// "Light  Medium  Heavy" over the column of moon controls.
struct IntensityColumnLabels: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(TagIntensity.allCases) { step in
                Text(step.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Color.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: MoonIntensityControl.segmentWidth)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityHidden(true)
    }
}

// MARK: - Ovulation test strip

/// A drawn test strip: the control line always, the test line by result (0 negative ... 3 peak).
struct OvulationStripGlyph: View {
    let result: Int

    var body: some View {
        let line = Event.EventType.menstrual.defaultPhaseColor
        let strength: Double = [0.0, 0.35, 0.9, 1][min(max(result, 0), 3)]
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DS.Color.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(DS.Color.separator, lineWidth: 1))
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(line.opacity(0.08))
                    .overlay(alignment: .top) {
                        VStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 1).fill(line.opacity(strength))
                                .frame(height: result == 3 ? 4 : 3).padding(.top, 5)
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1).fill(line.opacity(0.85)).frame(height: 3).padding(.bottom, 6)
                        }
                    }
                    .frame(height: 26)
                    .padding(.horizontal, 4).padding(.top, 9)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2).fill(DS.Color.primaryText.opacity(0.12))
                    .frame(width: 10, height: 14).padding(.bottom, 5)
            }
        }
        .frame(width: 26, height: 64)
        .accessibilityHidden(true)
    }
}

// MARK: - Count stepper

struct CountStepper: View {
    let label: String
    let count: Int
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onMinus) {
                Image(systemName: "minus").frame(width: 44, height: 38).contentShape(Rectangle())
            }
            .disabled(count == 0)
            .accessibilityLabel("One fewer \(label)")
            Text("\(count)")
                .font(.body.weight(.bold)).monospacedDigit()
                .foregroundColor(DS.Color.primaryText)
                .frame(minWidth: 26)
                .contentTransition(.numericText())
                .accessibilityHidden(true)
            Button(action: onPlus) {
                Image(systemName: "plus").frame(width: 44, height: 38).contentShape(Rectangle())
            }
            .accessibilityLabel("One more \(label)")
        }
        .font(.body.weight(.semibold))
        .foregroundColor(DS.Color.accent)
        .background(Capsule().fill(DS.Color.primaryText.opacity(0.06)))
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: count)
    }
}

// MARK: - Chips

/// A capsule chip: filled with the accent and a check when picked; a tag already logged that day is shown
/// as logged and cannot be picked again.
struct SheetChip: View {
    let label: String
    var symbol: String? = nil
    var isSelected: Bool = false
    var isLogged: Bool = false
    var count: Int = 0
    var height: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLogged {
                    Image(systemName: "checkmark.circle").imageScale(.small)
                } else if isSelected {
                    Image(systemName: "checkmark").imageScale(.small).fontWeight(.bold)
                } else if let symbol {
                    Image(systemName: symbol).imageScale(.small)
                }
                Text(label).lineLimit(1)
                if count > 1 {
                    Text("\(count)").font(.caption.weight(.bold)).monospacedDigit()
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(isSelected ? DS.Color.onAccent : (isLogged ? DS.Color.secondaryText : DS.Color.primaryText))
            .padding(.horizontal, 13)
            .frame(minHeight: max(height, 44))
            .background(
                Capsule().fill(isSelected ? DS.Color.accent : DS.Color.cardBackground.opacity(isLogged ? 0.5 : 1))
                    .frame(height: height)
            )
            .overlay(
                Capsule().strokeBorder(DS.Color.primaryText.opacity(isSelected ? 0 : 0.1), lineWidth: 1)
                    .frame(height: height)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLogged)
        .accessibilityValue(isLogged ? "Already logged for this day" : (isSelected ? (count > 1 ? "Picked \(count) times" : "Picked") : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A round glyph with its name under it: the mood grid and the quick log choices.
struct RoundGlyphButton: View {
    let label: String
    let symbol: String
    let isSelected: Bool
    var isLogged: Bool = false
    var diameter: CGFloat = 78
    var restFill: Color = DS.Color.cardBackground
    var restInk: Color = DS.Color.accent
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(RadialGradient(colors: [DS.Color.accent.mix(with: DS.Color.moon, by: 0.45), DS.Color.accent],
                                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: diameter * 0.7))
                            .shadow(color: DS.Color.accent.opacity(0.45), radius: 10, x: 0, y: 8)
                    } else {
                        Circle().fill(restFill)
                            .overlay(Circle().strokeBorder(DS.Color.primaryText.opacity(0.08), lineWidth: 1))
                    }
                    Image(systemName: symbol)
                        .font(.system(size: diameter * 0.36, weight: .regular))
                        .foregroundColor(isSelected ? DS.Color.onAccent : restInk)
                }
                .frame(width: diameter, height: diameter)
                .scaleEffect(isSelected && !reduceMotion ? 1.0 : 0.97)
                .opacity(isLogged ? 0.5 : 1)
                Text(label)
                    .font((diameter < 70 ? Font.caption : Font.footnote).weight(isSelected ? .bold : .medium))
                    .foregroundColor(DS.Color.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLogged)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isLogged ? "Already logged for this day" : (isSelected ? "Picked" : ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A picked tag in the tray: its strength moon or count, and a remove button.
struct TrayChip: View {
    let item: TagSelection.Item
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if let level = item.intensity {
                IntensityMoonGlyph(level: level, size: 13)
            }
            Text(item.pick.value)
                .font(.footnote.weight(.medium))
                .foregroundColor(DS.Color.primaryText)
                .lineLimit(1)
            if item.pick.isRepeatable {
                Text("\(item.count)").font(.footnote.weight(.bold)).monospacedDigit().foregroundColor(DS.Color.accent)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
                    .foregroundColor(DS.Color.secondaryText)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.pick.value)")
        }
        .padding(.leading, 11)
        .padding(.trailing, 2)
        .frame(height: 32)
        .background(Capsule().fill(DS.Color.cardBackground))
        .overlay(Capsule().strokeBorder(DS.Color.primaryText.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(TagFormLogic.trayAccessibilityLabel(item))
    }
}

/// A small rounded square with a white symbol, for rows (Intercourse, Hot Flashes, search results).
struct RowIconSquare: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack { ForEach(TagIntensity.allCases) { IntensityMoonGlyph(level: $0, size: 40) } }
        MoonIntensityControl(label: "Cramps", level: .medium) { _ in }
        HStack { ForEach(0..<4) { OvulationStripGlyph(result: $0) } }
    }
    .padding()
}
