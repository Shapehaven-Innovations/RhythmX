//  ModeSwitcher.swift
//  The three-segment pill under the Insights title: Cycle, Planning, Menopause. One tap switches the mode.

import SwiftUI

struct ModeSwitcher: View {
    @Binding var mode: TrackingMode
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
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                .fill(Color(UIColor.tertiarySystemFill))
        )
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
                .font(DS.Font.label.weight(isSelected ? .semibold : .medium))
                .foregroundColor(DS.Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, DS.Spacing.sm)
                .padding(.horizontal, DS.Spacing.xs)
                .frame(maxWidth: .infinity)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: DS.Radius.button - 2, style: .continuous)
                            .fill(DS.Color.cardBackground)
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
