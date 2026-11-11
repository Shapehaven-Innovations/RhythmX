//  SkinLogBody.swift
//
//  The Skin category body of the Add Tags sheet. Two styles build the same composite tag:
//  Chips (Where, What, Colour cards) and Body map (Face, Body front, Body back, then one card for the
//  picked area). "Add" puts one `TagPick(category: .skin, ...)` in the tray, replacing any tray pick for
//  the same area; saving goes through the tray like every other tag. At accessibility text sizes the
//  map is hidden and the Chips style is used.

import SwiftUI

struct SkinLogBody: View {
    @Binding var selection: TagSelection
    /// Parsed Skin tags already on the chosen day (for the dots on the map and the side tabs).
    let loggedToday: [SkinTag]
    @AppStorage("skinLogStyle") private var style: String = "chips"

    @State private var area: SkinTag.Area?
    @State private var kinds: Set<SkinTag.Kind> = []
    @State private var colour: SkinTag.Colour?
    @State private var side: BodyMapSide = .face

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }
    private var showsMap: Bool { style == "map" && !isAccessibilitySize }
    private var loggedAreas: Set<SkinTag.Area> { Set(loggedToday.map(\.area)) }

    /// The entry as picked so far; nil until an area and at least one type are picked.
    private var draft: SkinTag? {
        guard let area else { return nil }
        return SkinTag(area: area, kinds: kinds, colour: colour)
    }

    /// Clear on its own carries no colour, so the colour row is off while Clear is picked.
    private var colourEnabled: Bool { !kinds.contains(.clear) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isAccessibilitySize {
                Text("Pick the area from the list at larger text sizes.")
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Spacing.md)
            } else {
                SkinSegmentedTabs(options: [("chips", "Chips", false), ("map", "Body map", false)],
                                  selection: $style, label: "Log style")
                    .padding(.horizontal, 12)
            }

            if showsMap { mapStyle } else { chipsStyle }

            Text("Not here? Pick Other and add a note to the day.")
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Spacing.md)
        }
    }

    private func animate(_ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) { change() } }
    }

    // MARK: - Chips style

    private var chipsStyle: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                stepHeader(1, "Where", note: "one area per entry")
                FlowLayout(spacing: DS.Spacing.sm) {
                    ForEach(SkinTag.Area.allCases) { option in
                        SheetChip(label: option.rawValue, isSelected: area == option) { animate { area = option } }
                            .accessibilityHint(loggedAreas.contains(option) ? "Already logged today. Adding replaces it." : "")
                    }
                }
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardSurface())
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 12) {
                stepHeader(2, "What", note: "pick any")
                kindChips
                stepHeader(3, "Colour", note: "optional")
                    .padding(.top, 4)
                colourChips
                PrimaryButton(title: addTitle, action: add, isDisabled: draft == nil)
                    .padding(.top, 4)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardSurface())
            .padding(.horizontal, 12)
        }
    }

    private var addTitle: String {
        if let draft { return "Add " + draft.displayLabel }
        if let area { return "Add " + area.rawValue }
        return "Add"
    }

    private func stepHeader(_ number: Int, _ title: String, note: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundColor(DS.Color.onAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(DS.Color.accent))
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundColor(DS.Color.primaryText)
            Spacer(minLength: 8)
            Text(note)
                .font(.subheadline)
                .foregroundColor(DS.Color.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(title), \(note)")
        .accessibilityAddTraits(.isHeader)
    }

    private var kindChips: some View {
        FlowLayout(spacing: DS.Spacing.sm) {
            ForEach(SkinTag.Kind.allCases) { kind in
                SheetChip(label: kind.rawValue, isSelected: kinds.contains(kind)) { animate { toggle(kind) } }
                    .accessibilityHint(kind == .clear ? "Clears the other types" : "")
            }
        }
    }

    private func toggle(_ kind: SkinTag.Kind) {
        if kinds.contains(kind) {
            kinds.remove(kind)
        } else if kind == .clear {
            kinds = [.clear]
            colour = nil
        } else {
            kinds.remove(.clear)
            kinds.insert(kind)
        }
    }

    private var colourChips: some View {
        FlowLayout(spacing: DS.Spacing.sm) {
            ForEach(SkinTag.Colour.allCases) { option in
                SkinColourChip(colour: option, isSelected: colour == option) {
                    animate { colour = (colour == option) ? nil : option }
                }
                .disabled(!colourEnabled)
                .opacity(colourEnabled ? 1 : 0.45)
            }
        }
    }

    // MARK: - Body map style

    private var mapStyle: some View {
        VStack(spacing: 14) {
            SkinSegmentedTabs(options: BodyMapSide.allCases.map { s in
                                  (s, s.title, !loggedAreas.isDisjoint(with: BodyMapShapes.areas(for: s)))
                              },
                              selection: $side, label: "Map")
                .padding(.horizontal, 12)

            BodyMapView(side: side,
                        mode: .pick(selected: area, loggedToday: loggedAreas, onPick: { picked in
                            animate {
                                area = picked
                                // The head on the body map stands for the whole face: open the face map.
                                if picked == .face && side != .face { side = .face }
                            }
                        }))
                .frame(maxWidth: side == .face ? 300 : 340)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DS.Spacing.md)

            HStack(spacing: 6) {
                Circle().fill(SkinLogBody.loggedDot).frame(width: 8, height: 8).accessibilityHidden(true)
                Text("already logged today · tap an area to add")
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            HStack(spacing: DS.Spacing.sm) {
                if side == .face {
                    SheetChip(label: "Whole face", isSelected: area == .face) { animate { area = .face } }
                        .accessibilityHint("The whole face, not one area")
                }
                SheetChip(label: SkinTag.Area.other.rawValue, isSelected: area == .other) { animate { area = .other } }
                    .accessibilityHint("An area that is not on the map")
            }
            .frame(maxWidth: .infinity)

            mapCard
        }
    }

    /// The marker colour for "already logged today"; matches the map's logged dot.
    static var loggedDot: Color { DS.Color.accent }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let area {
                HStack(spacing: 10) {
                    Text(area.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Color.onAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DS.Color.accent))
                    Text("What does it look like?")
                        .font(.subheadline)
                        .foregroundColor(DS.Color.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                kindChips
                colourChips
                PrimaryButton(title: "Add to \(area.rawValue)", action: add, isDisabled: draft == nil)
                    .padding(.top, 4)
            } else {
                Text("Tap an area on the map to describe it.")
                    .font(.subheadline)
                    .foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardSurface())
        .padding(.horizontal, 12)
    }

    // MARK: - Add

    /// One tray entry per area: a new entry for an area replaces the tray's earlier one.
    private func add() {
        guard let tag = draft else { return }
        animate {
            for item in selection.items where item.pick.category == .skin
                && SkinTag.parse(item.pick.raw)?.area == tag.area {
                selection.remove(item.pick)
            }
            selection.add(TagPick(category: .skin, value: tag.value))
            kinds = []
            colour = nil
        }
    }
}

// MARK: - Pieces

/// A segmented row of options with an optional dot after a title (a side with areas logged today).
private struct SkinSegmentedTabs<Value: Hashable>: View {
    let options: [(Value, String, Bool)]
    @Binding var selection: Value
    let label: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option in
                let isOn = option.0 == selection
                Button { selection = option.0 } label: {
                    HStack(spacing: 5) {
                        Text(option.1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if option.2 {
                            Circle().fill(SkinLogBody.loggedDot).frame(width: 7, height: 7)
                        }
                    }
                    .font(.subheadline.weight(isOn ? .semibold : .medium))
                    .foregroundColor(DS.Color.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isOn ? DS.Color.cardBackground : Color.clear)
                            .shadow(color: isOn ? CardSurface.shadow : .clear, radius: 4, x: 0, y: 2)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel(option.1)
                .accessibilityValue(option.2 ? "Logged today" : "")
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(DS.Color.primaryText.opacity(0.06)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A colour chip: a fixed swatch dot (not themed, not the severity ramp) with a hairline ink outline, then the word.
private struct SkinColourChip: View {
    let colour: SkinTag.Colour
    let isSelected: Bool
    let action: () -> Void

    static func swatch(_ colour: SkinTag.Colour) -> Color {
        switch colour {
        case .red:       return Color(red: 0xD9 / 255, green: 0x53 / 255, blue: 0x4F / 255)
        case .pink:      return Color(red: 0xE8 / 255, green: 0xA0 / 255, blue: 0xB0 / 255)
        case .darkSpots: return Color(red: 0x6B / 255, green: 0x4A / 255, blue: 0x3A / 255)
        case .pale:      return Color(red: 0xF2 / 255, green: 0xE8 / 255, blue: 0xE0 / 255)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Self.swatch(colour))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(DS.Color.primaryText.opacity(0.4), lineWidth: 1))
                    .accessibilityHidden(true)
                Text(colour.rawValue).lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(isSelected ? DS.Color.onAccent : DS.Color.primaryText)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(Capsule().fill(isSelected ? DS.Color.accent : DS.Color.cardBackground).frame(height: 36))
            .overlay(Capsule().strokeBorder(DS.Color.primaryText.opacity(isSelected ? 0 : 0.1), lineWidth: 1).frame(height: 36))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Colour \(colour.rawValue)")
        .accessibilityValue(isSelected ? "Picked" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
