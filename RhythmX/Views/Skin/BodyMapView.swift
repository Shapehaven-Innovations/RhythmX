//  BodyMapView.swift
//
//  Draws a face or body map from `BodyMapShapes`. Pick mode: every region is a button whose hit area
//  is the region's own path. Display mode: every region is filled from the `SkinRamp` and labelled
//  with its percentage. Colour never carries the data alone: labels print the numbers and VoiceOver
//  reads them.

import SwiftUI

struct BodyMapView: View {
    enum Mode: Equatable {
        case pick(selected: SkinTag.Area?, loggedToday: Set<SkinTag.Area>, onPick: (SkinTag.Area) -> Void)
        case display(percentByArea: [SkinTag.Area: Int?], showsLabels: Bool)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case let (.pick(s1, l1, _), .pick(s2, l2, _)):
                return s1 == s2 && l1 == l2
            case let (.display(p1, sl1), .display(p2, sl2)):
                return p1 == p2 && sl1 == sl2
            default:
                return false
            }
        }
    }

    let side: BodyMapSide
    let mode: Mode
    /// nil: fills the proposed width; the Today card passes 120.
    var width: CGFloat? = nil
    /// Display mode: areas the caller labels outside the map with callouts; they get no inside label.
    var calloutAreas: Set<SkinTag.Area> = []
    /// Display mode: replaces an area's spoken value (e.g. the full-body head, which reads which face area
    /// it stands for), so a caller never needs a second VoiceOver element for the same number.
    var spokenValueOverrides: [SkinTag.Area: String] = [:]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var aspect: CGFloat { side == .face ? BodyMapShapes.faceAspect : BodyMapShapes.bodyAspect }

    /// Drawn bottom first, so the face outline sits under the regions and is hit-tested last.
    private var regions: [BodyMapRegion] {
        let all = BodyMapShapes.regions(for: side)
        return all.filter { $0.id == "face.outline" } + all.filter { $0.id != "face.outline" }
    }

    var body: some View {
        sized(
            GeometryReader { geo in
                let rect = CGRect(origin: .zero, size: geo.size)
                ZStack(alignment: .topLeading) {
                    BodyMapShapes.silhouette(for: side)
                        .applying(BodyMapRegion.transform(to: rect))
                        .fill(SkinRamp.colour(\.empty))
                        .accessibilityHidden(true)

                    if case .display = mode {
                        Color.clear
                            .accessibilityElement()
                            .accessibilityLabel(summaryLabel)
                            .accessibilitySortPriority(10_000)
                            .allowsHitTesting(false)
                    }

                    ForEach(regions) { region in
                        regionView(region, in: rect)
                    }
                }
                .frame(width: rect.width, height: rect.height)
            }
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func sized<Content: View>(_ content: Content) -> some View {
        if let width {
            content.frame(width: width, height: width * aspect)
        } else {
            content.aspectRatio(1 / aspect, contentMode: .fit)
        }
    }

    // MARK: Regions

    @ViewBuilder
    private func regionView(_ region: BodyMapRegion, in rect: CGRect) -> some View {
        switch mode {
        case let .pick(selected, loggedToday, onPick):
            let isSelected = selected == region.area
            let isLogged = loggedToday.contains(region.area)
            Button {
                onPick(region.area)
            } label: {
                ZStack(alignment: .topLeading) {
                    region.scaled(to: rect)
                        .fill(isSelected ? DS.Color.accent : SkinRamp.colour(\.empty))
                    region.scaled(to: rect)
                        .stroke(isSelected ? DS.Color.cardBackground : DS.Color.accent.opacity(0.3),
                                lineWidth: isSelected ? 3 : 1)
                    pickLabel(region, isSelected: isSelected, isLogged: isLogged, in: rect)
                }
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            }
            .buttonStyle(.plain)
            .contentShape(region.hitPath(in: rect))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
            .accessibilityLabel(region.area.rawValue)
            .accessibilityValue(isLogged ? "logged today" : "not logged today")
            .accessibilityHint("Selects this area")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilitySortPriority(region.sortPriority)

        case let .display(percentByArea, showsLabels):
            let percent = Self.percent(region.area, in: percentByArea)
            let isPeak = !showsLabels && peakArea(percentByArea) == region.area
            ZStack(alignment: .topLeading) {
                region.scaled(to: rect)
                    .fill(SkinRamp.fillColour(percent: percent))
                region.scaled(to: rect)
                    .stroke(DS.Color.cardBackground, lineWidth: rect.width < 200 ? 1 : 2)
                if isPeak {
                    region.scaled(to: rect)
                        .stroke(DS.Color.primaryText, lineWidth: 2)
                }
                if showsLabels && !calloutAreas.contains(region.area) {
                    displayLabel(region, percent: percent, in: rect)
                }
            }
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(region.area.rawValue)
            .accessibilityValue(spokenValueOverrides[region.area] ?? Self.spokenValue(percent))
            .accessibilitySortPriority(region.sortPriority)
        }
    }

    // MARK: Labels

    /// Singular on the two cheek regions; every other region uses the area name.
    static func displayName(for region: BodyMapRegion) -> String {
        region.area == .cheeks ? "Cheek" : region.area.rawValue
    }

    private func nameSize(_ rect: CGRect) -> CGFloat { rect.width * (side == .face ? 0.055 : 0.042) }
    private func percentSize(_ rect: CGRect) -> CGFloat { rect.width * (side == .face ? 0.08 : 0.055) }

    /// Label box: the region's width, centred on its label point.
    private func labelWidth(_ region: BodyMapRegion, in rect: CGRect) -> CGFloat {
        if region.id == "face.outline" { return rect.width * 0.5 }
        // Narrow regions (nose, neck, arms) let the label spill a little past their edge.
        return max(region.scaled(to: rect).boundingRect.width - 4, rect.width * 0.13)
    }

    private func pickLabel(_ region: BodyMapRegion, isSelected: Bool, isLogged: Bool, in rect: CGRect) -> some View {
        let size = nameSize(rect)
        return HStack(spacing: 3) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.8, weight: .bold))
            }
            Text(Self.displayName(for: region))
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(isSelected ? DS.Color.onAccent : DS.Color.accent)
        .overlay(alignment: .topTrailing) {
            if isLogged {
                Circle()
                    .fill(DS.Color.accent)
                    .overlay(Circle().stroke(DS.Color.cardBackground, lineWidth: 1))
                    .frame(width: 6, height: 6)
                    .offset(x: 6, y: -4)
            }
        }
        .frame(maxWidth: labelWidth(region, in: rect))
        .fixedSize(horizontal: false, vertical: true)
        .position(x: rect.minX + region.labelPoint.x * rect.width,
                  y: rect.minY + region.labelPoint.y * rect.height)
        .accessibilityHidden(true)
    }

    private func displayLabel(_ region: BodyMapRegion, percent: Int?, in rect: CGRect) -> some View {
        let textColour = percent == nil ? DS.Color.secondaryText : SkinRamp.textColor(percent: percent)
        let value = percent.map { "\($0)%" } ?? "–"
        let isOutline = region.id == "face.outline"
        let isNeck = region.area == .neck
        let isNarrow = region.scaled(to: rect).boundingRect.width < rect.width * 0.2
        return Group {
            if isOutline || isNeck {
                // The whole-face band and the neck are thin: one line.
                Text("\(Self.displayName(for: region)) \(value)")
                    .font(.system(size: nameSize(rect) * 0.85, weight: .semibold))
            } else {
                VStack(spacing: 0) {
                    Text(Self.displayName(for: region))
                        .font(.system(size: nameSize(rect), weight: .medium))
                    Text(value)
                        .font(.system(size: percentSize(rect), weight: .bold))
                        .monospacedDigit()
                }
            }
        }
        .foregroundStyle(textColour)
        .lineLimit(1)
        .minimumScaleFactor(isNarrow ? 0.5 : 0.7)
        .frame(maxWidth: labelWidth(region, in: rect))
        .fixedSize(horizontal: false, vertical: true)
        .position(x: rect.minX + region.labelPoint.x * rect.width,
                  y: rect.minY + region.labelPoint.y * rect.height)
        .accessibilityHidden(true)
    }

    // MARK: Values

    static func percent(_ area: SkinTag.Area, in map: [SkinTag.Area: Int?]) -> Int? {
        map[area] ?? nil
    }

    static func spokenValue(_ percent: Int?) -> String {
        percent.map { "\($0) percent" } ?? "not enough days"
    }

    /// The area on this side with the highest non-nil percent; ties go to the first in display order.
    private func peakArea(_ map: [SkinTag.Area: Int?]) -> SkinTag.Area? {
        var best: (area: SkinTag.Area, percent: Int)?
        for area in BodyMapShapes.areas(for: side) {
            guard let p = Self.percent(area, in: map) else { continue }
            if best == nil || p > best!.percent { best = (area, p) }
        }
        return best?.area
    }

    /// "Face map: chin 62 percent, jaw 51 percent, …", highest first, areas without enough days last.
    private var summaryLabel: String {
        guard case let .display(map, _) = mode else { return "" }
        let areas = BodyMapShapes.areas(for: side)
        let ranked = areas.enumerated().sorted { a, b in
            let pa = Self.percent(a.element, in: map) ?? -1
            let pb = Self.percent(b.element, in: map) ?? -1
            return pa != pb ? pa > pb : a.offset < b.offset
        }.map(\.element)
        let parts = ranked.map { "\($0.rawValue.lowercased()) \(Self.spokenValue(Self.percent($0, in: map)))" }
        return "\(side.title) map: " + parts.joined(separator: ", ")
    }
}

#Preview("Pick") {
    @Previewable @State var selected: SkinTag.Area? = .chin
    ScrollView {
        VStack(spacing: DS.Spacing.lg) {
            ForEach(BodyMapSide.allCases) { side in
                BodyMapView(side: side,
                            mode: .pick(selected: selected, loggedToday: [.forehead, .back], onPick: { selected = $0 }))
                    .frame(width: 300)
            }
        }
        .padding()
    }
    .background(DS.Color.pageBackground)
}

#Preview("Display") {
    let values: [SkinTag.Area: Int?] = [
        .forehead: 30, .cheeks: 19, .nose: 9, .jaw: 51, .chin: 62, .face: nil,
        .back: 41, .chest: 18, .shoulders: 12, .neck: 8, .arms: 4,
    ]
    ScrollView {
        VStack(spacing: DS.Spacing.lg) {
            ForEach(BodyMapSide.allCases) { side in
                BodyMapView(side: side, mode: .display(percentByArea: values, showsLabels: true))
                    .frame(width: 300)
            }
            BodyMapView(side: .face, mode: .display(percentByArea: values, showsLabels: false), width: 120)
        }
        .padding()
    }
    .background(DS.Color.pageBackground)
}
