//  BodyMapShapes.swift
//  Face and body map geometry in unit coordinates. Pure data: no colours, no views.
//
//  Unit space is 0...1 on both axes. The face map is drawn into a 1:1.2 portrait box
//  (height = 1.2 x width), the body maps into a 1.3:1 landscape box (height = 0.83 x width): one continuous
//  figure cropped at the upper thigh, centred, with margin either side for the outside label pills.
//  Authored in a 100 x 120 face box and a 130 x 108 body box, then divided into unit space.

import SwiftUI

enum BodyMapSide: String, CaseIterable, Identifiable {
    case face, front, back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .face: return "Face"
        case .front: return "Body front"
        case .back: return "Body back"
        }
    }
}

/// One tappable region in unit coordinates (0...1 in both axes of the face and body boxes).
struct BodyMapRegion: Identifiable, Equatable {
    let id: String                 // "face.cheekLeft", "front.shoulderRight", ...
    let area: SkinTag.Area
    let path: Path                 // unit path
    let labelPoint: CGPoint        // unit point for the name / percentage
    let sortPriority: Double       // VoiceOver order, higher first (top to bottom, left to right)
    let minimumHitInset: CGFloat   // negative inset for small regions (nose, neck), in unit widths
    /// Pick mode: where the name is drawn as a pill outside the figure (with a leader to `labelPoint`), because
    /// the region is too small for 11pt text. The pill is part of the tap target. nil: the name sits inside.
    let pill: CGPoint?

    /// Smallest hit box on either axis, in points.
    static let minimumHitSide: CGFloat = 44

    init(id: String, area: SkinTag.Area, path: Path, labelPoint: CGPoint, minimumHitInset: CGFloat = 0,
         pill: CGPoint? = nil) {
        self.pill = pill
        self.id = id
        self.area = area
        self.path = path
        self.labelPoint = labelPoint
        self.minimumHitInset = minimumHitInset
        self.sortPriority = BodyMapRegion.priority(for: labelPoint)
    }

    /// Top to bottom, then left to right. Rows in the layout differ by at least 0.01 in y,
    /// which outweighs the whole x term.
    static func priority(for point: CGPoint) -> Double {
        Double(1 - point.y) * 1000 + Double(1 - point.x)
    }

    func scaled(to rect: CGRect) -> Path {
        path.applying(BodyMapRegion.transform(to: rect))
    }

    /// The scaled path grown by `-minimumHitInset * rect.width` on every side, and never
    /// smaller than 44 x 44 points: a too-small box is padded with a centred rounded rectangle.
    func hitPath(in rect: CGRect) -> Path {
        let scaledPath = scaled(to: rect)
        var hit = scaledPath
        let grow = -minimumHitInset * rect.width
        if grow > 0 {
            let ring = scaledPath.strokedPath(StrokeStyle(lineWidth: grow * 2, lineCap: .round, lineJoin: .round))
            hit = scaledPath.union(ring)
        }
        let box = hit.boundingRect
        let side = BodyMapRegion.minimumHitSide
        if box.width < side || box.height < side {
            let pad = CGRect(x: box.midX - max(box.width, side) / 2,
                             y: box.midY - max(box.height, side) / 2,
                             width: max(box.width, side),
                             height: max(box.height, side))
            hit = hit.union(Path(roundedRect: pad, cornerRadius: min(pad.width, pad.height) / 2))
        }
        return hit
    }

    static func transform(to rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height)
    }

    static func == (lhs: BodyMapRegion, rhs: BodyMapRegion) -> Bool {
        lhs.id == rhs.id && lhs.area == rhs.area && lhs.path == rhs.path
            && lhs.labelPoint == rhs.labelPoint && lhs.sortPriority == rhs.sortPriority
            && lhs.minimumHitInset == rhs.minimumHitInset && lhs.pill == rhs.pill
    }
}

enum BodyMapShapes {
    static let faceAspect: CGFloat = 120.0 / 100.0
    static let bodyAspect: CGFloat = 108.0 / 130.0

    static let smallRegionInset: CGFloat = -0.03

    static func regions(for side: BodyMapSide) -> [BodyMapRegion] {
        switch side {
        case .face: return faceRegions
        case .front: return frontRegions
        case .back: return backRegions
        }
    }

    static func silhouette(for side: BodyMapSide) -> Path {
        switch side {
        case .face: return faceSilhouette
        case .front, .back: return bodySilhouette
        }
    }

    /// Stroke-only drawing (brows, closed eyes, nose base, lips; collarbones, spine). Decoration, never a target.
    static func guides(for side: BodyMapSide) -> Path {
        switch side {
        case .face: return faceGuides
        case .front: return frontGuides
        case .back: return backGuides
        }
    }

    /// Distinct areas on that side, in `SkinTag.Area` order. The face side also lists Whole face, which is
    /// picked with a chip under the map rather than a region.
    static func areas(for side: BodyMapSide) -> [SkinTag.Area] {
        var present = Set(regions(for: side).map(\.area))
        if side == .face { present.insert(.face) }
        return SkinTag.Area.allCases.filter { present.contains($0) }
    }

    // MARK: - Path data (absolute SVG commands: M L H V C Q Z)

    /// Parses `d` and maps every point through `map`.
    private static func svg(_ d: String, _ map: (CGFloat, CGFloat) -> CGPoint) -> Path {
        let spaced = d.replacingOccurrences(of: ",", with: " ")
            .reduce(into: "") { out, ch in
                if ch.isLetter { out += " \(ch) " } else { out.append(ch) }
            }
        let tokens = spaced.split(separator: " ").map(String.init)
        var path = Path()
        var i = 0
        var cmd = ""
        var cur = CGPoint.zero
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func pt() -> CGPoint { let x = num(); let y = num(); return map(x, y) }
        // Raw coordinates are needed to track H and V.
        var raw = CGPoint.zero
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = tokens[i]; i += 1 }
            switch cmd {
            case "M": let x = num(), y = num(); raw = CGPoint(x: x, y: y); cur = map(x, y); path.move(to: cur)
            case "L": let x = num(), y = num(); raw = CGPoint(x: x, y: y); cur = map(x, y); path.addLine(to: cur)
            case "H": let x = num(); raw.x = x; cur = map(raw.x, raw.y); path.addLine(to: cur)
            case "V": let y = num(); raw.y = y; cur = map(raw.x, raw.y); path.addLine(to: cur)
            case "C":
                let c1 = pt(), c2 = pt(), x = num(), y = num()
                raw = CGPoint(x: x, y: y); cur = map(x, y)
                path.addCurve(to: cur, control1: c1, control2: c2)
            case "Q":
                let c = pt(), x = num(), y = num()
                raw = CGPoint(x: x, y: y); cur = map(x, y)
                path.addQuadCurve(to: cur, control: c)
            case "Z", "z": path.closeSubpath()
            default: i += 1
            }
        }
        return path
    }

    /// Cuts `shapes` (in order) out of `outline`; each later shape loses what the earlier ones took, so the
    /// regions tile the outline with no overlap.
    private static func tile(_ shapes: [Path], in outline: Path) -> [Path] {
        var taken = Path()
        var out: [Path] = []
        for shape in shapes {
            var piece = shape.intersection(outline)
            if !taken.isEmpty { piece = piece.subtracting(taken) }
            out.append(piece)
            taken = taken.isEmpty ? piece : taken.union(piece)
        }
        return out
    }

    // MARK: - Face (box 100 x 120)

    private static func facePath(_ d: String) -> Path {
        svg(d) { CGPoint(x: $0 / 100, y: $1 / 120) }
    }

    private static let faceOutline = facePath(
        "M50 3 C72 3 90 18 90 44 C90 60 87 74 80 88 C73 102 62 117 50 117 C38 117 27 102 20 88 C13 74 10 60 10 44 C10 18 28 3 50 3 Z")

    private static let faceSilhouette: Path = {
        var p = Path()
        p.addPath(facePath("M10.5 44 C5 41 2.5 49 4 59 C5.2 67 8.5 72 11.8 70 Z"))
        p.addPath(facePath("M89.5 44 C95 41 97.5 49 96 59 C94.8 67 91.5 72 88.2 70 Z"))
        p.addPath(faceOutline)
        return p
    }()

    private static let faceGuides = facePath(
        "M22 45 Q31 40 41 44 M59 44 Q69 40 78 45 M24 53 Q32 57 40 53 M60 53 Q68 57 76 53 "
        + "M42 80 Q50 84 58 80 M41 95 Q45.5 93 50 94.5 Q54.5 93 59 95 M41 95 Q50 101 59 95")

    /// Forehead above the brows, the T-shaped nose, the chin under the nose, a jaw band along each jawline, and
    /// a cheek on each side. Eyes sit in the cheeks and the mouth in the chin: the stored areas are fixed.
    private static let faceRegions: [BodyMapRegion] = {
        let cuts: [(String, SkinTag.Area, String, CGPoint, CGFloat)] = [
            ("face.forehead", .forehead, "M0 0 H100 V41 Q50 34 0 41 Z", CGPoint(x: 50, y: 22), 0),
            ("face.nose", .nose,
             "M44.5 36 H55.5 C55.5 56 60 68 62.5 75 C63.5 82 56 84 50 84 C44 84 36.5 82 37.5 75 C40 68 44.5 56 44.5 36 Z",
             CGPoint(x: 50, y: 70), smallRegionInset),
            ("face.chin", .chin, "M36 92 Q50 74 64 92 L62 120 H38 Z", CGPoint(x: 50, y: 104), 0),
            ("face.jawLeft", .jaw, "M0 52 L36 92 L38 120 H0 Z", CGPoint(x: 29, y: 98), 0),
            ("face.jawRight", .jaw, "M100 52 L64 92 L62 120 H100 Z", CGPoint(x: 71, y: 98), 0),
            ("face.cheekLeft", .cheeks, "M0 36 H50 V104 L38 104 L36 92 L0 52 Z", CGPoint(x: 27, y: 64), 0),
            ("face.cheekRight", .cheeks, "M100 36 H50 V104 L62 104 L64 92 L100 52 Z", CGPoint(x: 73, y: 64), 0),
        ]
        let pieces = tile(cuts.map { facePath($0.2) }, in: faceOutline)
        let regions = zip(cuts, pieces).map { cut, piece in
            BodyMapRegion(id: cut.0, area: cut.1, path: piece,
                          labelPoint: CGPoint(x: cut.3.x / 100, y: cut.3.y / 120), minimumHitInset: cut.4)
        }
        // Reading order for VoiceOver: top to bottom, left to right.
        return regions.sorted { $0.sortPriority > $1.sortPriority }
    }()

    // MARK: - Body (box 130 x 108, figure centred: x + 15)

    /// Every body coordinate goes through here: the figure is authored 0...100 wide and narrowed by `bodyWidth`
    /// about its centre line, so shoulders stand about three head-widths across.
    private static let bodyWidth: CGFloat = 0.94
    private static func bodyPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: (50 + (x - 50) * bodyWidth + 15) / 130, y: y / 108)
    }
    private static func bodyPath(_ d: String) -> Path { svg(d, bodyPoint) }
    private static func mirrored(_ d: String) -> String {
        // Mirror x about the figure centre (50) in a command string of absolute coordinates.
        let spaced = d.replacingOccurrences(of: ",", with: " ").reduce(into: "") { out, ch in
            if ch.isLetter { out += " \(ch) " } else { out.append(ch) }
        }
        let tokens = spaced.split(separator: " ").map(String.init)
        var out: [String] = []
        var cmd = "", argIndex = 0
        for t in tokens {
            if t.first!.isLetter { cmd = t; argIndex = 0; out.append(t); continue }
            let v = Double(t) ?? 0
            if cmd == "V" || cmd == "Z" { out.append(t) }
            else if cmd == "H" { out.append(String(100 - v)) }
            else { out.append(argIndex % 2 == 0 ? String(100 - v) : t); argIndex += 1 }
        }
        return out.joined(separator: " ")
    }

    private static let headEllipse = Path(ellipseIn: CGRect(x: (39.6 + 15) / 130, y: 0.6 / 108,
                                                           width: 20.8 / 130, height: 24.8 / 108))

    /// One closed outline: neck, shoulders, arms hanging clear of the torso, hips, cropped at the upper thigh.
    /// The right half is authored; the left half is its mirror.
    private static let bodyOutline: Path = {
        typealias P = (CGFloat, CGFloat)
        enum Seg { case line(P), curve(P, P, P) }
        let start: P = (55.5, 22)
        let segs: [Seg] = [
            .line((55.8, 28.5)),
            .curve((56.6, 31), (66, 31.5), (72, 33.5)),
            .curve((78, 35), (82, 39), (82.5, 46)),
            .curve((83, 53), (84.5, 60), (85.5, 67)),
            .curve((86.5, 76), (88.5, 84), (90.5, 92)),
            .curve((91.8, 96), (92, 99.5), (89.8, 100.5)),
            .curve((87.5, 101.5), (86, 98.5), (85, 95)),
            .curve((83.5, 87), (81, 79), (79, 72)),
            .curve((77.5, 65), (76, 57), (74, 50.5)),
            .curve((73.8, 57), (71.5, 61), (69.8, 65)),
            .curve((68.8, 71), (73.8, 76), (73.8, 84)),
            .curve((73.8, 92), (73.2, 99), (72, 106)),
            .line((50, 106)),
        ]
        func m(_ q: P) -> CGPoint { bodyPoint(q.0, q.1) }
        func mm(_ q: P) -> CGPoint { bodyPoint(100 - q.0, q.1) }
        var p = Path()
        p.move(to: m(start))
        var ends: [P] = [start]
        for seg in segs {
            switch seg {
            case let .line(e): p.addLine(to: m(e)); ends.append(e)
            case let .curve(c1, c2, e): p.addCurve(to: m(e), control1: m(c1), control2: m(c2)); ends.append(e)
            }
        }
        // Left half: the same segments walked backwards, mirrored.
        for idx in stride(from: segs.count - 1, through: 0, by: -1) {
            let target = ends[idx]
            switch segs[idx] {
            case .line: p.addLine(to: mm(target))
            case let .curve(c1, c2, _): p.addCurve(to: mm(target), control1: mm(c2), control2: mm(c1))
            }
        }
        p.closeSubpath()
        return p
    }()

    private static let bodySilhouette: Path = {
        var p = Path()
        p.addPath(headEllipse)
        p.addPath(bodyOutline)
        return p
    }()

    private static let frontGuides = bodyPath(
        "M44 36 Q38 37 33 41 M56 36 Q62 37 67 41 M36 58 Q43 63 49 59 M51 59 Q57 63 64 58 M50 79 V80.5")
    private static let backGuides = bodyPath(
        "M50 35 V86 M38 45 Q41 54 45.5 57 M62 45 Q59 54 54.5 57 M44 96 Q50 99 56 96")

    private static let neckCut = "M43.6 25.6 H56.4 V30 L62 34 H38 L43.6 30 Z"
    private static let shoulderCutR = "M57 22 H100 V47 H74.4 L69 39 L58 33 Z"
    private static let armCutR = "M74.4 47 H100 V108 H74.4 Z"
    private static let chestCut = "M25.6 47 L31 39 L42 33 H58 L69 39 L74.4 47 V66 H25.6 Z"
    private static let backCut = "M25.6 47 L31 39 L42 33 H58 L69 39 L74.4 47 V90 H25.6 Z"

    private static func bodyRegions(_ side: BodyMapSide) -> [BodyMapRegion] {
        func u(_ x: CGFloat, _ y: CGFloat) -> CGPoint { bodyPoint(x, y) }
        var shapes: [Path] = [bodyPath(neckCut), bodyPath(shoulderCutR), bodyPath(mirrored(shoulderCutR)),
                              bodyPath(armCutR), bodyPath(mirrored(armCutR)),
                              bodyPath(side == .front ? chestCut : backCut)]
        shapes = tile(shapes, in: bodyOutline)
        let s = side.rawValue
        var list: [BodyMapRegion] = []
        if side == .front {
            list.append(BodyMapRegion(id: "front.head", area: .face, path: headEllipse, labelPoint: u(50, 13)))
        }
        list += [
            BodyMapRegion(id: "\(s).neck", area: .neck, path: shapes[0], labelPoint: u(50, 29),
                          minimumHitInset: smallRegionInset, pill: u(22, 11)),
            BodyMapRegion(id: "\(s).shoulderLeft", area: .shoulders, path: shapes[2], labelPoint: u(28, 38),
                          pill: u(6, 28)),
            BodyMapRegion(id: "\(s).shoulderRight", area: .shoulders, path: shapes[1], labelPoint: u(72, 38)),
            BodyMapRegion(id: "\(s).armLeft", area: .arms, path: shapes[4], labelPoint: u(19, 66), pill: u(-1, 68)),
            BodyMapRegion(id: "\(s).armRight", area: .arms, path: shapes[3], labelPoint: u(81, 66)),
            side == .front
                ? BodyMapRegion(id: "front.chest", area: .chest, path: shapes[5], labelPoint: u(50, 52))
                : BodyMapRegion(id: "back.back", area: .back, path: shapes[5], labelPoint: u(50, 62)),
        ]
        return list.sorted { $0.sortPriority > $1.sortPriority }
    }

    private static let frontRegions = bodyRegions(.front)
    private static let backRegions = bodyRegions(.back)
}
