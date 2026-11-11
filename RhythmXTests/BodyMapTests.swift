//  BodyMapTests.swift
//  Geometry rules for the face and body maps: coverage, no overlaps, label points, hit sizes, VoiceOver order.

import XCTest
import SwiftUI
@testable import RhythmX

final class BodyMapTests: XCTestCase {

    private func aspect(_ side: BodyMapSide) -> CGFloat {
        side == .face ? BodyMapShapes.faceAspect : BodyMapShapes.bodyAspect
    }

    private func rect(_ side: BodyMapSide, width: CGFloat = 300) -> CGRect {
        CGRect(x: 12, y: 20, width: width, height: width * aspect(side))
    }

    /// `Path.contains` is unreliable on tiny unit-space paths, so hit tests run at 1000x.
    private func contains(_ region: BodyMapRegion, _ p: CGPoint) -> Bool {
        region.path.applying(CGAffineTransform(scaleX: 1000, y: 1000)).contains(CGPoint(x: p.x * 1000, y: p.y * 1000))
    }

    func testTitles() {
        XCTAssertEqual(BodyMapSide.face.title, "Face")
        XCTAssertEqual(BodyMapSide.front.title, "Body front")
        XCTAssertEqual(BodyMapSide.back.title, "Body back")
        XCTAssertEqual(BodyMapSide.allCases, [.face, .front, .back])
    }

    func testEveryAreaExceptOtherHasARegionOnSomeSide() {
        let face = Set(BodyMapShapes.areas(for: .face))
        let front = Set(BodyMapShapes.areas(for: .front))
        let back = Set(BodyMapShapes.areas(for: .back))

        XCTAssertTrue(face.isSuperset(of: [.face, .forehead, .cheeks, .chin, .jaw, .nose]))
        XCTAssertTrue(front.isSuperset(of: [.neck, .chest, .shoulders, .arms]))
        XCTAssertTrue(back.isSuperset(of: [.back, .shoulders, .arms, .neck]))

        let all = face.union(front).union(back)
        for area in SkinTag.Area.allCases where area != .other {
            XCTAssertTrue(all.contains(area), "\(area) has no region")
        }
        XCTAssertFalse(all.contains(.other))
    }

    func testAreasMatchRegionsAndAreDistinct() {
        for side in BodyMapSide.allCases {
            let areas = BodyMapShapes.areas(for: side)
            XCTAssertEqual(areas.count, Set(areas).count, "\(side) areas repeat")
            // Whole face is a chip under the face map, not a region.
            let drawn = Set(BodyMapShapes.regions(for: side).map(\.area))
            XCTAssertEqual(Set(areas), side == .face ? drawn.union([.face]) : drawn)
        }
    }

    func testRegionIdsAreUniqueAndPrefixedBySide() {
        var seen = Set<String>()
        for side in BodyMapSide.allCases {
            for region in BodyMapShapes.regions(for: side) {
                XCTAssertTrue(region.id.hasPrefix(side.rawValue + "."), region.id)
                XCTAssertTrue(seen.insert(region.id).inserted, "duplicate \(region.id)")
            }
        }
        let face = BodyMapShapes.regions(for: .face)
        XCTAssertEqual(face.filter { $0.area == .cheeks }.count, 2)
        XCTAssertEqual(face.filter { $0.area == .jaw }.count, 2)
        XCTAssertNil(face.first { $0.area == .face }, "Whole face is a chip, not a region")
    }

    func testRegionsDoNotOverlap() {
        for side in BodyMapSide.allCases {
            let regions = BodyMapShapes.regions(for: side)
            for i in 0..<40 {
                for j in 0..<40 {
                    let p = CGPoint(x: (CGFloat(i) + 0.5) / 40, y: (CGFloat(j) + 0.5) / 40)
                    let hits = regions.filter { contains($0, p) }.map(\.id)
                    XCTAssertLessThanOrEqual(hits.count, 1, "\(side) overlap at \(p): \(hits)")
                }
            }
        }
    }

    func testLabelPointsLieInsideTheirRegion() {
        for side in BodyMapSide.allCases {
            for region in BodyMapShapes.regions(for: side) {
                XCTAssertTrue(contains(region, region.labelPoint), region.id)
                let others = BodyMapShapes.regions(for: side).filter { $0.id != region.id }
                for other in others {
                    XCTAssertFalse(contains(other, region.labelPoint), "\(region.id) label in \(other.id)")
                }
            }
        }
    }

    func testHitPathsAreAtLeast44Points() {
        for side in BodyMapSide.allCases {
            let r = rect(side)
            for region in BodyMapShapes.regions(for: side) {
                let box = region.hitPath(in: r).boundingRect
                XCTAssertGreaterThanOrEqual(box.width, 44, "\(region.id) width \(box.width)")
                XCTAssertGreaterThanOrEqual(box.height, 44, "\(region.id) height \(box.height)")
                // The hit path still covers the drawn region.
                let centre = CGPoint(x: r.minX + region.labelPoint.x * r.width,
                                     y: r.minY + region.labelPoint.y * r.height)
                XCTAssertTrue(region.hitPath(in: r).contains(centre), region.id)
            }
        }
    }

    func testSmallRegionsGetANegativeHitInset() {
        let nose = BodyMapShapes.regions(for: .face).first { $0.area == .nose }!
        XCTAssertEqual(nose.minimumHitInset, -0.03, accuracy: 0.0001)
        for side in [BodyMapSide.front, .back] {
            let neck = BodyMapShapes.regions(for: side).first { $0.area == .neck }!
            XCTAssertEqual(neck.minimumHitInset, -0.03, accuracy: 0.0001)
        }
        // The inset grows the nose sideways beyond its drawn width.
        let r = rect(.face)
        XCTAssertGreaterThan(nose.hitPath(in: r).boundingRect.width,
                             nose.scaled(to: r).boundingRect.width)
    }

    func testSortPriorityIsTopToBottom() {
        for side in BodyMapSide.allCases {
            let regions = BodyMapShapes.regions(for: side)
            for a in regions {
                for b in regions where a.sortPriority > b.sortPriority {
                    XCTAssertLessThanOrEqual(a.labelPoint.y, b.labelPoint.y, "\(a.id) before \(b.id)")
                    if a.labelPoint.y == b.labelPoint.y {
                        XCTAssertLessThan(a.labelPoint.x, b.labelPoint.x, "\(a.id) before \(b.id)")
                    }
                }
            }
        }
    }

    func testScaledPathContainsCentre() {
        for side in BodyMapSide.allCases {
            let r = rect(side, width: 240)
            for region in BodyMapShapes.regions(for: side) {
                let p = CGPoint(x: r.minX + region.labelPoint.x * r.width,
                                y: r.minY + region.labelPoint.y * r.height)
                XCTAssertTrue(region.scaled(to: r).contains(p), region.id)
                XCTAssertTrue(r.insetBy(dx: -0.5, dy: -0.5).contains(region.scaled(to: r).boundingRect), region.id)
            }
        }
    }

    func testRegionsAndSilhouetteStayInTheUnitBox() {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        for side in BodyMapSide.allCases {
            let silhouette = BodyMapShapes.silhouette(for: side)
            XCTAssertFalse(silhouette.isEmpty)
            XCTAssertTrue(unit.contains(silhouette.boundingRect), "\(side) silhouette")
            for region in BodyMapShapes.regions(for: side) {
                XCTAssertFalse(region.path.isEmpty, region.id)
                XCTAssertTrue(unit.contains(region.path.boundingRect), region.id)
            }
        }
    }

    func testPillsStayInTheUnitBoxAndOnlyTheSmallRegionsHaveOne() {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        for side in [BodyMapSide.front, .back] {
            for region in BodyMapShapes.regions(for: side) {
                if let pill = region.pill { XCTAssertTrue(unit.contains(pill), region.id) }
            }
            XCTAssertNotNil(BodyMapShapes.regions(for: side).first { $0.area == .neck }?.pill)
            XCTAssertNil(BodyMapShapes.regions(for: side).first { $0.area == .chest || $0.area == .back }?.pill)
        }
    }

    func testFaceZonesCoverTheOutlineWithNoDeadBand() {
        // Sample inside the face: every point belongs to a region (the old map left an unlabelled band).
        let regions = BodyMapShapes.regions(for: .face)
        for (x, y) in [(0.3, 0.3), (0.5, 0.45), (0.27, 0.45), (0.73, 0.45), (0.5, 0.7), (0.35, 0.75), (0.5, 0.95)] {
            let p = CGPoint(x: x, y: y)
            XCTAssertTrue(regions.contains { contains($0, p) }, "no region at \(p)")
        }
    }
}
