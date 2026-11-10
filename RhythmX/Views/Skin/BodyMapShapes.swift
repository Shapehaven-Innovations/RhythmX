//  BodyMapShapes.swift
//  Face and body map geometry in unit coordinates. Pure data: no colours, no views.
//
//  Unit space is 0...1 on both axes. The face map is drawn into a 1:1.4 portrait box
//  (height = 1.4 x width), the body maps into a 1:2.2 box, so a shape that should look
//  round on screen has a vertical radius of (horizontal radius / aspect) in unit space.

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

/// One tappable region in unit coordinates (0...1 in both axes of a 1:1.4 portrait box for face, 1:2.2 for body).
struct BodyMapRegion: Identifiable, Equatable {
    let id: String                 // "face.cheekLeft", "front.shoulderRight", ...
    let area: SkinTag.Area
    let path: Path                 // unit path
    let labelPoint: CGPoint        // unit point for the name / percentage
    let sortPriority: Double       // VoiceOver order, higher first (top to bottom, left to right)
    let minimumHitInset: CGFloat   // negative inset for small regions (nose, neck), in unit widths

    /// Smallest hit box on either axis, in points.
    static let minimumHitSide: CGFloat = 44

    init(id: String, area: SkinTag.Area, path: Path, labelPoint: CGPoint, minimumHitInset: CGFloat = 0) {
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
            && lhs.minimumHitInset == rhs.minimumHitInset
    }
}

enum BodyMapShapes {
    static let faceAspect: CGFloat = 1.4
    static let bodyAspect: CGFloat = 2.2

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

    /// Distinct areas on that side, in `SkinTag.Area` order.
    static func areas(for side: BodyMapSide) -> [SkinTag.Area] {
        let present = Set(regions(for: side).map(\.area))
        return SkinTag.Area.allCases.filter { present.contains($0) }
    }

    // MARK: - Shape helpers (unit space)

    private static func ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    /// Rounded rectangle whose corners look circular after scaling into a box of `aspect`.
    private static func rounded(_ rect: CGRect, radius: CGFloat, aspect: CGFloat) -> Path {
        let rx = min(radius, rect.width / 2)
        let ry = min(radius / aspect, rect.height / 2)
        return Path(roundedRect: rect, cornerSize: CGSize(width: rx, height: ry), style: .continuous)
    }

    /// A capsule along the longer screen axis.
    private static func capsule(_ rect: CGRect, aspect: CGFloat) -> Path {
        let screenW = rect.width
        let screenH = rect.height * aspect
        return rounded(rect, radius: min(screenW, screenH) / 2, aspect: aspect)
    }

    // MARK: - Face (1:1.4)

    private static let faceOval = ellipse(cx: 0.5, cy: 0.5, rx: 0.40, ry: 0.48)
    private static let chinOval = ellipse(cx: 0.5, cy: 0.855, rx: 0.15, ry: 0.11)

    /// Point on an ellipse at angle `t` (radians, 0 = right, pi/2 = bottom in a y-down space).
    private static func point(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, _ t: CGFloat) -> CGPoint {
        CGPoint(x: cx + rx * cos(t), y: cy + ry * sin(t))
    }

    /// Angle on the face oval where it crosses height `y`, on the left (`left == true`) or right half.
    private static func faceAngle(atY y: CGFloat, left: Bool) -> CGFloat {
        let s = asin((y - 0.5) / 0.48)        // -pi/2 (top) ... pi/2 (bottom), right half
        return left ? .pi - s : s
    }

    /// Appends the arc of an ellipse from angle `from` to `to` as short line segments.
    private static func addArc(_ p: inout Path, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat,
                               from: CGFloat, to: CGFloat, steps: Int = 32) {
        for i in 0...steps {
            let t = from + (to - from) * CGFloat(i) / CGFloat(steps)
            p.addLine(to: point(cx: cx, cy: cy, rx: rx, ry: ry, t))
        }
    }

    /// Top cap of the face oval above y = 0.27.
    private static let foreheadPath: Path = {
        var p = Path()
        let start = faceAngle(atY: 0.27, left: true)                 // left crossing
        let end = faceAngle(atY: 0.27, left: false) + 2 * .pi         // right crossing, going over the top
        p.move(to: point(cx: 0.5, cy: 0.5, rx: 0.40, ry: 0.48, start))
        addArc(&p, cx: 0.5, cy: 0.5, rx: 0.40, ry: 0.48, from: start, to: end)
        p.closeSubpath()
        return p
    }()

    /// Lower side wedge of the face below y = 0.70, from the outline to the midline, minus the chin.
    private static func jawPath(left: Bool) -> Path {
        var p = Path()
        let top = faceAngle(atY: 0.70, left: left)
        let bottom = CGFloat.pi / 2
        p.move(to: CGPoint(x: 0.5, y: 0.70))
        p.addLine(to: point(cx: 0.5, cy: 0.5, rx: 0.40, ry: 0.48, top))
        addArc(&p, cx: 0.5, cy: 0.5, rx: 0.40, ry: 0.48, from: top, to: bottom)
        // Up the midline to the chin's bottom, round the chin's outer half to its top.
        p.addLine(to: CGPoint(x: 0.5, y: 0.965))
        addArc(&p, cx: 0.5, cy: 0.855, rx: 0.15, ry: 0.11,
               from: .pi / 2, to: left ? 1.5 * .pi : -.pi / 2)
        p.closeSubpath()
        return p
    }

    private static let faceRegions: [BodyMapRegion] = {
        let forehead = foreheadPath
        let jawLeft = jawPath(left: true)
        let jawRight = jawPath(left: false)
        let nose = capsule(CGRect(x: 0.43, y: 0.33, width: 0.14, height: 0.32), aspect: faceAspect)

        return [
            BodyMapRegion(id: "face.forehead", area: .forehead, path: forehead,
                          labelPoint: CGPoint(x: 0.5, y: 0.15)),
            BodyMapRegion(id: "face.cheekLeft", area: .cheeks,
                          path: ellipse(cx: 0.27, cy: 0.53, rx: 0.13, ry: 0.12),
                          labelPoint: CGPoint(x: 0.27, y: 0.53)),
            BodyMapRegion(id: "face.nose", area: .nose, path: nose,
                          labelPoint: CGPoint(x: 0.5, y: 0.53), minimumHitInset: smallRegionInset),
            BodyMapRegion(id: "face.cheekRight", area: .cheeks,
                          path: ellipse(cx: 0.73, cy: 0.53, rx: 0.13, ry: 0.12),
                          labelPoint: CGPoint(x: 0.73, y: 0.53)),
            BodyMapRegion(id: "face.jawLeft", area: .jaw, path: jawLeft,
                          labelPoint: CGPoint(x: 0.25, y: 0.77)),
            BodyMapRegion(id: "face.jawRight", area: .jaw, path: jawRight,
                          labelPoint: CGPoint(x: 0.75, y: 0.77)),
            BodyMapRegion(id: "face.chin", area: .chin, path: chinOval,
                          labelPoint: CGPoint(x: 0.5, y: 0.86)),
            // Whole face, drawn under the others and hit-tested last.
            BodyMapRegion(id: "face.outline", area: .face, path: faceOval,
                          labelPoint: CGPoint(x: 0.5, y: 0.97)),
        ]
    }()

    private static let faceSilhouette: Path = {
        var p = Path()
        p.addPath(ellipse(cx: 0.07, cy: 0.52, rx: 0.05, ry: 0.08))
        p.addPath(ellipse(cx: 0.93, cy: 0.52, rx: 0.05, ry: 0.08))
        p.addPath(faceOval)
        return p
    }()

    // MARK: - Body (1:2.2)

    private static let headOval = ellipse(cx: 0.5, cy: 0.075, rx: 0.16, ry: 0.07)
    private static let neckRect = CGRect(x: 0.43, y: 0.15, width: 0.14, height: 0.04)
    private static let armLeftRect = CGRect(x: 0.12, y: 0.25, width: 0.10, height: 0.30)
    private static let armRightRect = CGRect(x: 0.78, y: 0.25, width: 0.10, height: 0.30)

    private static func neck(_ side: BodyMapSide) -> BodyMapRegion {
        BodyMapRegion(id: "\(side.rawValue).neck", area: .neck, path: capsule(neckRect, aspect: bodyAspect),
                      labelPoint: CGPoint(x: 0.5, y: 0.17), minimumHitInset: smallRegionInset)
    }

    private static func shoulders(_ side: BodyMapSide) -> [BodyMapRegion] {
        [
            BodyMapRegion(id: "\(side.rawValue).shoulderLeft", area: .shoulders,
                          path: ellipse(cx: 0.30, cy: 0.215, rx: 0.11, ry: 0.03),
                          labelPoint: CGPoint(x: 0.30, y: 0.215)),
            BodyMapRegion(id: "\(side.rawValue).shoulderRight", area: .shoulders,
                          path: ellipse(cx: 0.70, cy: 0.215, rx: 0.11, ry: 0.03),
                          labelPoint: CGPoint(x: 0.70, y: 0.215)),
        ]
    }

    private static func arms(_ side: BodyMapSide) -> [BodyMapRegion] {
        [
            BodyMapRegion(id: "\(side.rawValue).armLeft", area: .arms,
                          path: capsule(armLeftRect, aspect: bodyAspect),
                          labelPoint: CGPoint(x: 0.17, y: 0.40)),
            BodyMapRegion(id: "\(side.rawValue).armRight", area: .arms,
                          path: capsule(armRightRect, aspect: bodyAspect),
                          labelPoint: CGPoint(x: 0.83, y: 0.40)),
        ]
    }

    /// Chest on the front: upper torso with a rounded top.
    private static let chestPath: Path = {
        let rect = CGRect(x: 0.31, y: 0.25, width: 0.38, height: 0.15)
        return Path(roundedRect: rect,
                    cornerRadii: RectangleCornerRadii(topLeading: 0.06 / bodyAspect, bottomLeading: 0,
                                                      bottomTrailing: 0, topTrailing: 0.06 / bodyAspect),
                    style: .continuous)
    }()

    /// Back: the whole torso.
    private static let backPath = rounded(CGRect(x: 0.31, y: 0.25, width: 0.38, height: 0.27),
                                          radius: 0.06, aspect: bodyAspect)

    private static let frontRegions: [BodyMapRegion] = {
        [
            BodyMapRegion(id: "front.head", area: .face, path: headOval, labelPoint: CGPoint(x: 0.5, y: 0.075)),
            neck(.front),
        ] + shoulders(.front) + [
            BodyMapRegion(id: "front.chest", area: .chest, path: chestPath, labelPoint: CGPoint(x: 0.5, y: 0.33)),
        ] + arms(.front)
    }()

    private static let backRegions: [BodyMapRegion] = {
        [neck(.back)] + shoulders(.back) + [
            BodyMapRegion(id: "back.back", area: .back, path: backPath, labelPoint: CGPoint(x: 0.5, y: 0.38)),
        ] + arms(.back)
    }()

    /// Head, neck, torso, arms, hips and legs. Legs and hips are silhouette only.
    private static let bodySilhouette: Path = {
        var p = Path()
        p.addPath(headOval)
        p.addPath(capsule(neckRect, aspect: bodyAspect))
        p.addPath(ellipse(cx: 0.30, cy: 0.215, rx: 0.11, ry: 0.03))
        p.addPath(ellipse(cx: 0.70, cy: 0.215, rx: 0.11, ry: 0.03))
        // Torso tapering a little to the hips.
        var torso = Path()
        torso.move(to: CGPoint(x: 0.31, y: 0.25))
        torso.addLine(to: CGPoint(x: 0.69, y: 0.25))
        torso.addLine(to: CGPoint(x: 0.69, y: 0.47))
        torso.addQuadCurve(to: CGPoint(x: 0.66, y: 0.56), control: CGPoint(x: 0.69, y: 0.52))
        torso.addLine(to: CGPoint(x: 0.34, y: 0.56))
        torso.addQuadCurve(to: CGPoint(x: 0.31, y: 0.47), control: CGPoint(x: 0.31, y: 0.52))
        torso.closeSubpath()
        p.addPath(torso)
        p.addPath(capsule(armLeftRect, aspect: bodyAspect))
        p.addPath(capsule(armRightRect, aspect: bodyAspect))
        p.addPath(capsule(CGRect(x: 0.36, y: 0.57, width: 0.12, height: 0.41), aspect: bodyAspect))
        p.addPath(capsule(CGRect(x: 0.52, y: 0.57, width: 0.12, height: 0.41), aspect: bodyAspect))
        return p
    }()
}
