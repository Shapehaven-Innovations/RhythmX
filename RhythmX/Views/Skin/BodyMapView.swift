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
    /// The 11pt floor for pick labels grows with Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var pickFloor: CGFloat = 11

    private var isPick: Bool { if case .pick = mode { return true } else { return false } }
    /// Today card: a Whole face tag has no region of its own, so it tints every face zone that has no value.
    var wholeFaceFills = false

    private var aspect: CGFloat { side == .face ? BodyMapShapes.faceAspect : BodyMapShapes.bodyAspect }

    private var regions: [BodyMapRegion] { BodyMapShapes.regions(for: side) }

    var body: some View {
        sized(
            GeometryReader { geo in
                let rect = CGRect(origin: .zero, size: geo.size)
                ZStack(alignment: .topLeading) {
                    let figure = BodyMapShapes.silhouette(for: side).applying(BodyMapRegion.transform(to: rect))
                    figure.fill(isPick ? SkinRamp.pageSilhouetteColour : SkinRamp.silhouetteColour)
                        .accessibilityHidden(true)
                    figure.stroke(DS.Color.primaryText.opacity(0.2), lineWidth: 0.75)
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

                    // Feature guides (brows, eyes, lips, collarbones, spine): decoration only.
                    BodyMapShapes.guides(for: side)
                        .applying(BodyMapRegion.transform(to: rect))
                        .stroke(DS.Color.primaryText.opacity(0.22),
                                style: StrokeStyle(lineWidth: max(0.8, rect.width * 0.004), lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .frame(width: rect.width, height: rect.height)
                .mask(bottomFade)
            }
        )
        .accessibilityElement(children: .contain)
    }

    /// The body is cropped at the upper thigh: its last fifth fades out instead of ending in a hard edge.
    @ViewBuilder
    private var bottomFade: some View {
        if side == .face {
            Color.black
        } else {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8),
                                   .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        }
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
                        .fill(isSelected ? DS.Color.accent : SkinRamp.pageSilhouetteColour)
                    // A gap in the page colour separates the regions instead of a faint hairline.
                    region.scaled(to: rect)
                        .stroke(DS.Color.pageBackground, lineWidth: max(2, rect.width * 0.008))
                    if let pill = region.pill {
                        pillView(region, at: pill, isSelected: isSelected, isLogged: isLogged, in: rect)
                    } else if regions.contains(where: { $0.area == region.area && $0.pill != nil }) {
                        // The mirror region (right arm, right shoulder) is named by its pill on the other side.
                        EmptyView()
                    } else {
                        pickLabel(region, isSelected: isSelected, isLogged: isLogged, in: rect)
                    }
                }
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            }
            .buttonStyle(.plain)
            .contentShape(hitShape(region, in: rect))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
            .accessibilityLabel(region.area.rawValue)
            .accessibilityValue(isLogged ? "logged today" : "not logged today")
            .accessibilityHint(region.area == .face && side != .face ? "Selects the whole face and opens the face map" : "Selects this area")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilitySortPriority(region.sortPriority)

        case let .display(percentByArea, showsLabels):
            let own = Self.percent(region.area, in: percentByArea)
            let percent = (own == nil && wholeFaceFills && side == .face) ? Self.percent(.face, in: percentByArea) : own
            let isPeak = !showsLabels && peakArea(percentByArea) == region.area
            ZStack(alignment: .topLeading) {
                region.scaled(to: rect)
                    .fill(percent == nil || percent == 0 ? SkinRamp.regionColour : SkinRamp.fillColour(percent: percent))
                region.scaled(to: rect)
                    .stroke(DS.Color.cardBackground, lineWidth: rect.width < 200 ? 1.5 : 2.5)
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
    /// Pick labels never go under 11pt.
    private func pickNameSize(_ rect: CGRect) -> CGFloat { max(pickFloor, nameSize(rect)) }

    /// Approximate size of a pill, from its text.
    private func pillSize(_ region: BodyMapRegion, in rect: CGRect) -> CGSize {
        let size = pickNameSize(rect)
        let text = Self.displayName(for: region)
        // Room for the checkmark is always reserved, so a selected pill does not grow over its leader.
        return CGSize(width: CGFloat(text.count) * size * 0.6 + 22 + size * 0.8 + 3, height: max(30, size * 2.2))
    }

    private func hitShape(_ region: BodyMapRegion, in rect: CGRect) -> Path {
        var hit = region.hitPath(in: rect)
        // The neck's padded target must not take taps on the head, which opens the face map.
        if side == .front, region.area == .neck,
           let head = regions.first(where: { $0.id == "front.head" }) {
            hit = hit.subtracting(head.scaled(to: rect))
        }
        if let pill = region.pill {
            let c = CGPoint(x: rect.minX + pill.x * rect.width, y: rect.minY + pill.y * rect.height)
            let sz = pillSize(region, in: rect)
            let box = CGRect(x: c.x - max(sz.width, 44) / 2, y: c.y - max(sz.height, 44) / 2,
                             width: max(sz.width, 44), height: max(sz.height, 44))
            hit = hit.union(Path(roundedRect: box, cornerRadius: 16))
        }
        return hit
    }

    /// The name as a pill outside the figure with a leader to the region; the pill selects the region too.
    private func pillView(_ region: BodyMapRegion, at pill: CGPoint, isSelected: Bool, isLogged: Bool,
                          in rect: CGRect) -> some View {
        let size = pickNameSize(rect)
        let c = CGPoint(x: rect.minX + pill.x * rect.width, y: rect.minY + pill.y * rect.height)
        let target = CGPoint(x: rect.minX + region.labelPoint.x * rect.width,
                             y: rect.minY + region.labelPoint.y * rect.height)
        let sz = pillSize(region, in: rect)
        return ZStack(alignment: .topLeading) {
            Path { p in p.move(to: c); p.addLine(to: target) }
                .stroke(DS.Color.accent.opacity(0.55), lineWidth: 1)
            Circle().fill(DS.Color.accent).frame(width: 5, height: 5).position(target)
            HStack(spacing: 3) {
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: size * 0.8, weight: .bold))
                }
                Text(Self.displayName(for: region))
                    .font(.system(size: size, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? DS.Color.onAccent : DS.Color.accent)
            .padding(.horizontal, 10)
            .frame(minWidth: sz.width, minHeight: sz.height)
            .background(Capsule().fill(isSelected ? DS.Color.accent : DS.Color.cardBackground))
            .overlay(Capsule().stroke(DS.Color.accent.opacity(isSelected ? 0 : 0.45), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if isLogged {
                    Circle().fill(DS.Color.accent)
                        .overlay(Circle().stroke(DS.Color.cardBackground, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                        .offset(x: 3, y: -3)
                }
            }
            .position(c)
        }
        .accessibilityHidden(true)
    }
    private func percentSize(_ rect: CGRect) -> CGFloat { rect.width * (side == .face ? 0.08 : 0.055) }

    /// Label box: the region's width, centred on its label point.
    private func labelWidth(_ region: BodyMapRegion, in rect: CGRect) -> CGFloat {
        // Narrow regions (nose, neck, arms) let the label spill a little past their edge.
        return max(region.scaled(to: rect).boundingRect.width - 4, rect.width * 0.13)
    }

    private func pickLabel(_ region: BodyMapRegion, isSelected: Bool, isLogged: Bool, in rect: CGRect) -> some View {
        let size = pickNameSize(rect)
        return HStack(spacing: 3) {
            // Narrow zones (the jaw bands) drop the checkmark so the name stays on the figure.
            if isSelected && labelWidth(region, in: rect) >= 46 {
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
                    .frame(width: 9, height: 9)
                    .offset(x: 8, y: -5)
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
        let isNeck = region.area == .neck
        let isNarrow = region.scaled(to: rect).boundingRect.width < rect.width * 0.2
        return Group {
            if isNeck {
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
        for area in Set(regions.map(\.area)).sorted(by: { SkinTag.Area.allCases.firstIndex(of: $0)! < SkinTag.Area.allCases.firstIndex(of: $1)! }) {
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
