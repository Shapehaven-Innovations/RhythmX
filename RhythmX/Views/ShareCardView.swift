//  ShareCardView.swift
//  Draws one `ShareCard` at 360 by 450 points in the current theme, and renders it to a 1080 by 1350 PNG
//  with ImageRenderer. Plain gradients and shapes only (ImageRenderer does not draw MeshGradient or glass
//  reliably). Colours come straight from the theme palette for the appearance, so the image matches the app.

import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct ShareCardView: View {
    let card: ShareCard
    let palette: Palette

    private var isMinimal: Bool { card.style == .minimal }
    private var base: Color { DS.Color.solid(isMinimal ? palette.card : palette.accent) }
    private var ink: Color { DS.Color.solid(isMinimal ? palette.ink : palette.onAccent) }
    private var moon: Color { DS.Color.solid(palette.moon) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            if !isMinimal { CardStars(color: ink).opacity(0.55) }
            art
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(.top, 22)
                .padding(.trailing, 22)
            VStack(alignment: .leading, spacing: 0) {
                content
                Spacer(minLength: 12)
                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 96)
            .padding(.bottom, 24)
        }
        .frame(width: ShareCardModel.pointSize.width, height: ShareCardModel.pointSize.height)
        .foregroundStyle(ink)
        .environment(\.dynamicTypeSize, .large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityDescription)
        .accessibilityAddTraits(.isImage)
    }

    // MARK: - Background and art

    @ViewBuilder
    private var background: some View {
        switch card.style {
        case .minimal:
            base
        case .moon:
            ZStack {
                base
                RadialGradient(colors: [moon.opacity(0.40), moon.opacity(0)], center: UnitPoint(x: 0.85, y: 0.08),
                               startRadius: 0, endRadius: 250)
            }
        case .aura:
            let glow = card.phase.map { $0.defaultPhaseColor } ?? moon
            ZStack {
                base
                RadialGradient(colors: [glow.opacity(0.70), glow.opacity(0)], center: UnitPoint(x: 0.2, y: 0.1),
                               startRadius: 0, endRadius: 260)
                RadialGradient(colors: [moon.opacity(0.45), moon.opacity(0)], center: UnitPoint(x: 0.9, y: 0.9),
                               startRadius: 0, endRadius: 230)
            }
        }
    }

    @ViewBuilder
    private var art: some View {
        if isMinimal {
            if let day = card.cycleDay {
                CardPhaseRing(day: day, track: DS.Color.solid(palette.muted).opacity(0.18), marker: base)
                    .frame(width: 72, height: 72)
            } else {
                CardMoon(phase: nil, lit: DS.Color.solid(palette.accent), halo: DS.Color.solid(palette.accent))
                    .frame(width: 72, height: 72)
            }
        } else {
            CardMoon(phase: card.phase, lit: moon, halo: moon)
                .frame(width: 96, height: 96)
        }
    }

    // MARK: - Content

    private var eyebrow: some View {
        Text(card.eyebrow).font(.system(size: 15, weight: .semibold)).opacity(0.85)
    }

    private func bigNumber(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold).monospacedDigit())
            .tracking(-size * 0.04)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private var content: some View {
        switch card.kind {
        case .cycleDay, .hotFlashes:
            eyebrow
            if let big = card.big { bigNumber(big, size: 150).padding(.top, 2) }
            if let subtitle = card.subtitle {
                Text(subtitle).font(.system(size: 21, weight: .semibold)).padding(.top, 2)
            }
            if let detail = card.detail {
                Text(detail).font(.system(size: 16)).opacity(0.85).padding(.top, 6)
            }
        case .possibleToday:
            eyebrow
            VStack(alignment: .leading, spacing: 12) {
                ForEach(card.items, id: \.label) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(ink.opacity(0.16)))
                        Text(item.label)
                            .font(.system(size: 22, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .padding(.top, 16)
        case .phase:
            eyebrow
            if let big = card.big {
                Text(big).font(.system(size: 46, weight: .bold)).lineLimit(2).minimumScaleFactor(0.6).padding(.top, 10)
            }
            if let detail = card.detail {
                Text(detail).font(.system(size: 17)).lineSpacing(4).opacity(0.9).padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .bestChances:
            eyebrow
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let big = card.big { bigNumber(big, size: card.bigIsNumber ? 130 : 96) }
                if let side = card.bigSide { Text(side).font(.system(size: 34, weight: .bold)) }
            }
            .padding(.top, 2)
            if let detail = card.detail {
                Text(detail).font(.system(size: 16)).opacity(0.9).padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            estimateAndDisclaimer.padding(.top, 10)
        case .combined, .minimal:
            eyebrow
            HStack(alignment: .bottom, spacing: 12) {
                if let big = card.big { bigNumber(big, size: 96) }
                VStack(alignment: .leading, spacing: 2) {
                    if let side = card.bigSide { Text(side).font(.system(size: 19, weight: .semibold)) }
                    if let detail = card.bigSideDetail {
                        Text(detail).font(.system(size: 19, weight: .medium)).opacity(0.8)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, 14)
            }
            .padding(.top, 4)
            Rectangle().fill(ink.opacity(0.2)).frame(height: 1).padding(.vertical, 16)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(card.facts, id: \.lead) { fact in
                    Text("\(Text(fact.lead).bold()) \(fact.rest)")
                        .font(.system(size: 16))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            estimateAndDisclaimer.padding(.top, 12)
        }
    }

    @ViewBuilder
    private var estimateAndDisclaimer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let estimate = card.estimateLine {
                Text(estimate).font(.system(size: 14, weight: .semibold))
            }
            if let disclaimer = card.disclaimer {
                Text(disclaimer).font(.system(size: 12)).opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image("ExportLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(card.footer).font(.system(size: 12, weight: .bold)).tracking(0.3)
            Spacer(minLength: 8)
            if let sharer = card.sharerLine {
                Text(sharer).font(.system(size: 12)).lineLimit(1)
            }
        }
        .opacity(0.85)
    }

    // MARK: - Rendering

    /// The 1080 by 1350 PNG of a card, or nil when ImageRenderer cannot draw it.
    @MainActor
    static func pngData(for card: ShareCard, palette: Palette, isDark: Bool) -> Data? {
        let renderer = ImageRenderer(content: ShareCardView(card: card, palette: palette)
            .environment(\.colorScheme, isDark ? .dark : .light))
        renderer.scale = ShareCardModel.renderScale
        renderer.proposedSize = ProposedViewSize(ShareCardModel.pointSize)
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }
}

/// A card as the share sheet sends it: PNG data in memory, never a temporary file.
struct ShareCardImage: Identifiable, Transferable, Equatable {
    let id: String
    let fileName: String
    let title: String
    let accessibilityDescription: String
    let png: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName { $0.fileName }
    }

    var uiImage: UIImage? { UIImage(data: png) }
}

/// Full size card images, rendered only when the share sheet or the partner view asks for them and kept per
/// card, theme, light or dark, and name, so a thumbnail tap or a scroll never renders anything.
@MainActor
final class ShareCardRenderCache {
    static let shared = ShareCardRenderCache()
    private var images: [String: Data] = [:]
    private var order: [String] = []
    private let limit = 12
    /// How many images were actually rendered (tests).
    private(set) var renderCount = 0

    nonisolated static func key(card: ShareCard, themeID: String, isDark: Bool, name: String) -> String {
        "\(String(describing: card))|\(themeID)|\(isDark)|\(name)"
    }

    func png(for card: ShareCard, palette: Palette, isDark: Bool, key: String) -> Data? {
        if let cached = images[key] { return cached }
        guard let data = ShareCardView.pngData(for: card, palette: palette, isDark: isDark) else { return nil }
        renderCount += 1
        images[key] = data
        order.append(key)
        if order.count > limit { images[order.removeFirst()] = nil }
        return data
    }
}

/// A card the share sheet sends as PNG data in memory. The image is made only when iOS asks for it.
struct ShareCardItem: Identifiable, Transferable {
    let card: ShareCard
    let palette: Palette
    let isDark: Bool
    let key: String
    let cache: ShareCardRenderCache

    init(card: ShareCard, palette: Palette, isDark: Bool, themeID: String, name: String,
         cache: ShareCardRenderCache) {
        self.card = card
        self.palette = palette
        self.isDark = isDark
        self.key = ShareCardRenderCache.key(card: card, themeID: themeID, isDark: isDark, name: name)
        self.cache = cache
    }

    var id: String { card.id }
    var title: String { card.pickerTitle }

    struct RenderFailed: Error {}

    @MainActor
    func renderNow() -> Data? { cache.png(for: card, palette: palette, isDark: isDark, key: key) }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard let data = await item.renderNow() else { throw RenderFailed() }
            return data
        }
        .suggestedFileName { $0.card.fileName }
    }
}

/// A card drawn small, as on the Share screen.
struct ShareCardThumbnail: View {
    let card: ShareCard
    let palette: Palette
    let width: CGFloat

    var body: some View {
        let scale = width / ShareCardModel.pointSize.width
        ShareCardView(card: card, palette: palette)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: ShareCardModel.pointSize.height * scale, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 28 * scale + 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28 * scale + 6, style: .continuous)
                .strokeBorder(card.style == .minimal ? DS.Color.separator : .clear, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }
}

// MARK: - Art

/// The moon in its halo: two soft rings and the lit part for the phase (full in Menopause).
private struct CardMoon: View {
    let phase: Event.EventType?
    let lit: Color
    let halo: Color

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(halo.opacity(0.16))
                Circle().fill(halo.opacity(0.26)).frame(width: d * 0.70, height: d * 0.70)
                litShape(d * 0.70)
            }
            .frame(width: d, height: d)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func litShape(_ d: CGFloat) -> some View {
        switch phase {
        case .ovulation?:
            Circle().strokeBorder(lit, lineWidth: max(2, d / 18)).frame(width: d, height: d)
        case .menstrual?, nil:
            Circle().fill(lit).frame(width: d, height: d)
        case .follicular?, .luteal?:
            // Luteal: lit on the right with a dark sliver on the left; follicular the mirror image.
            let dx = (phase == .luteal ? -1 : 1) * d * 0.62
            Circle().fill(lit).frame(width: d, height: d)
                .mask(
                    ZStack {
                        Rectangle()
                        Circle().frame(width: d, height: d).offset(x: dx).blendMode(.destinationOut)
                    }
                    .compositingGroup()
                )
        }
    }
}

/// The four phase arcs of a 28 day cycle with today's marker, for the minimal card.
private struct CardPhaseRing: View {
    let day: Int
    let track: Color
    let marker: Color

    var body: some View {
        let counts = CycleGenerator.dayCounts(cycleLength: 28)
        let total = Double(max(counts.values.reduce(0, +), 1))
        var cursor = 0.0
        let arcs: [(Event.EventType, Double, Double)] = Event.EventType.allCases.map { phase in
            let start = cursor
            cursor += Double(counts[phase] ?? 0) / total
            return (phase, start, cursor)
        }
        let position = min(Double(max(day, 1)) - 0.5, total) / total
        return GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let r = d / 2 - 5
            ZStack {
                ForEach(arcs, id: \.0) { arc in
                    Circle()
                        .trim(from: arc.1 + 0.012, to: max(arc.1 + 0.013, arc.2 - 0.012))
                        .stroke(arc.0.defaultPhaseColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                let angle = Angle.degrees(position * 360 - 90)
                Circle()
                    .fill(arcs.first { position >= $0.1 && position <= $0.2 }?.0.defaultPhaseColor ?? track)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(marker, lineWidth: 3))
                    .offset(x: r * cos(angle.radians), y: r * sin(angle.radians))
            }
            .frame(width: d, height: d)
        }
        .accessibilityHidden(true)
    }
}

/// A fixed scatter of small stars (the same on every render).
private struct CardStars: View {
    let color: Color
    private static let points: [(CGFloat, CGFloat, CGFloat)] = {
        var seed: UInt64 = 13
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }
        return (0..<20).map { _ in (next(), next() * 0.82, 1 + next() * 1.4) }
    }()

    var body: some View {
        Canvas { context, size in
            for (x, y, r) in Self.points {
                let rect = CGRect(x: x * size.width, y: y * size.height, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.35 + Double(r) * 0.15)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
