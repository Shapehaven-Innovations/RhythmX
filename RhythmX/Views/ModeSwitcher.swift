//  ModeSwitcher.swift
//  The three-segment pill: Cycle, Planning, Menopause. One tap switches the mode. Today shows the compact
//  glass pill at the top of the page, under the week strip.

import SwiftUI

struct ModeSwitcher: View {
    @Binding var mode: TrackingMode
    /// A small glass capsule sized to its labels (Today) instead of the full-width rounded track.
    var compact: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection

    var body: some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 2))
            : AnyLayout(HStackLayout(spacing: 2))) {
            ForEach(TrackingMode.allCases) { candidate in
                segment(candidate)
            }
        }
        .padding(compact ? 3 : 2)
        .background {
            if compact {
                Capsule().fill(Color.clear).glassEffect(.regular, in: Capsule())
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                    .fill(Color(UIColor.tertiarySystemFill))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tracking mode")
        .accessibilityValue(mode.title)
    }

    private func segment(_ candidate: TrackingMode) -> some View {
        let isSelected = candidate == mode
        return Button {
            guard !isSelected else { return }
            if reduceMotion {
                mode = candidate
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { mode = candidate }
            }
        } label: {
            Text(candidate.title)
                .font((compact ? Font.footnote : DS.Font.label).weight(isSelected ? .semibold : .medium))
                .foregroundColor(compact && isSelected ? DS.Color.onAccent : DS.Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, compact ? 7 : DS.Spacing.sm)
                .padding(.horizontal, compact ? 14 : DS.Spacing.xs)
                .frame(maxWidth: compact ? nil : .infinity)
                .frame(minHeight: compact ? 36 : nil)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: compact ? 18 : DS.Radius.button - 2, style: .continuous)
                            .fill(compact ? DS.Color.accent : DS.Color.cardBackground)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                            .matchedGeometryEffect(id: "selected", in: selection)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    struct Host: View {
        @State var mode: TrackingMode = .cycle
        var body: some View {
            ModeSwitcher(mode: $mode).padding()
        }
    }
    return Host()
}
