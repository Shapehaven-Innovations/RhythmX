//  SkinTagTests.swift

import XCTest
@testable import RhythmX

@MainActor
final class SkinTagTests: XCTestCase {

    func testComposeCanonicalOrderAndNoCommas() {
        let t = SkinTag(area: .chin, kinds: [.breakout, .acne], colour: .red)
        XCTAssertEqual(t?.raw, "Skin:Chin/Acne+Breakout/Red")
        XCTAssertFalse(t!.raw.contains(","))
        XCTAssertEqual(t?.value, "Chin/Acne+Breakout/Red")
        XCTAssertEqual(t?.isFlare, true)
    }

    func testClearIsExclusive() {
        let t = SkinTag(area: .face, kinds: [.clear, .acne], colour: .red)
        XCTAssertEqual(t?.raw, "Skin:Face/Clear")
        XCTAssertEqual(t?.isFlare, false)
    }

    func testEmptyKindsIsNil() {
        XCTAssertNil(SkinTag(area: .face, kinds: [], colour: nil))
    }

    func testParseRoundTrip() {
        for area in SkinTag.Area.allCases {
            for kind in SkinTag.Kind.allCases {
                for colour in [nil] + SkinTag.Colour.allCases.map(Optional.some) {
                    let t = SkinTag(area: area, kinds: [kind], colour: colour)!
                    XCTAssertEqual(SkinTag.parse(t.raw), t, t.raw)
                }
            }
        }
        let multi = SkinTag(area: .jaw, kinds: [.dry, .flaky, .irritated], colour: .darkSpots)!
        XCTAssertEqual(SkinTag.parse(multi.raw), multi)
    }

    func testParseRejectsMalformed() {
        for s in ["Skin:", "Skin:Chin", "Skin:Elbow/Acne", "Skin:Chin/Shiny", "Skin:Chin/Acne/Blue",
                  "Symptom:Cramps", "Skin:Chin/Acne/Red/Extra"] {
            XCTAssertNil(SkinTag.parse(s), s)
        }
    }

    func testLegacyAcneMapsToFaceAcne() {
        let t = SkinTag.fromLegacyAcne("Other:Acne")
        XCTAssertEqual(t, SkinTag(area: .face, kinds: [.acne], colour: nil))
        XCTAssertNil(SkinTag.fromLegacyAcne("Other:Bloating"))
    }

    func testParseAnyPrefersSkin() {
        XCTAssertEqual(SkinTag.parseAny("Skin:Back/Breakout")?.area, .back)
        XCTAssertEqual(SkinTag.parseAny("Other:Acne")?.area, .face)
        XCTAssertNil(SkinTag.parseAny("Mood:Happy"))
        XCTAssertTrue(SkinTag.isSkinRaw("Skin:Chin"))
        XCTAssertFalse(SkinTag.isSkinRaw("Other:Acne"))
    }

    func testDisplayLabel() {
        XCTAssertEqual(SkinTag(area: .chin, kinds: [.acne, .breakout], colour: .red)?.displayLabel, "Chin · Acne, Breakout · Red")
        XCTAssertEqual(SkinTag(area: .back, kinds: [.breakout], colour: nil)?.displayLabel, "Back · Breakout")
        XCTAssertEqual(SkinTag(area: .face, kinds: [.clear], colour: nil)?.displayLabel, "Face · Clear")
    }

    func testTagParserLabelUsesDisplayLabel() {
        XCTAssertEqual(TagParser.label(for: "Skin:Chin/Acne+Breakout/Red"), "Chin · Acne, Breakout · Red")
        XCTAssertEqual(TagParser.label(for: "Symptom:Cramps"), "Cramps")
    }

    func testSplitKeepsDarkSpots() {
        XCTAssertEqual(TagParser.split("Skin:Chin/Acne/Dark spots, Mood:Happy").count, 2)
    }
}
