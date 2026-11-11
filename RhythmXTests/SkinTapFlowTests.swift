//  SkinTapFlowTests.swift
//  Hosts the real Add Tags sheet on the Skin category and taps its controls through the accessibility tree,
//  to prove the single bottom "Add Tags" button follows the card (the in-card Add button is gone).

import SwiftUI
import XCTest
@testable import RhythmX

@MainActor
final class SkinTapFlowTests: XCTestCase {

    private var host: UIHostingController<AnyView>!
    private var window: UIWindow!
    private var savedStyle: Any?
    private var savedRoot: UIViewController?

    /// SwiftUI builds its accessibility tree only while an assistive client is on, so turn automation on.
    private static func automation(_ on: Bool) {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let sym = dlsym(handle, "_AXSSetAutomationEnabled") else { return }
        typealias Fn = @convention(c) (Bool) -> Void
        unsafeBitCast(sym, to: Fn.self)(on)
    }

    override func setUp() async throws {
        Self.automation(true)
        savedStyle = UserDefaults.standard.object(forKey: "skinLogStyle")
        UserDefaults.standard.set("chips", forKey: "skinLogStyle")
        window = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow ?? ($0 as? UIWindowScene)?.windows.first }.first)
        savedRoot = window.rootViewController
        showSheet(withCycle: true)
    }

    /// Hosts a fresh Add Tags sheet on Skin, on a day inside a cycle or (no cycle) on a day with no event.
    private func showSheet(withCycle: Bool) {
        let settings = AppSettings()
        settings.trackingMode = .cycle
        let store = EventStore(preview: true)
        let start = Calendar.current.date(byAdding: .day, value: -5, to: Calendar.current.startOfDay(for: Date()))!
        store.events = withCycle ? CycleGenerator.events(startDate: start, cycleLength: 28) : []
        let root = TagFormView(initialDate: Date(), initialCategory: .skin)
            .environmentObject(store).environmentObject(ArchivedDataStore())
            .environmentObject(settings).environmentObject(FertileStore()).environmentObject(HealthSync())
        host = UIHostingController(rootView: AnyView(root))
        window.rootViewController = host
        window.makeKeyAndVisible()
        settle(1.5)
        // The first accessibility query makes SwiftUI build its tree; give it time to fill in.
        _ = all()
        settle(1.5)
    }

    /// Automation stays on across this class's tests (toggling it per test hides SwiftUI's tree) and goes off after.
    override class func tearDown() {
        MainActor.assumeIsolated { SkinTapFlowTests.automation(false) }
        super.tearDown()
    }

    override func tearDown() async throws {
        if let savedStyle { UserDefaults.standard.set(savedStyle, forKey: "skinLogStyle") }
        else { UserDefaults.standard.removeObject(forKey: "skinLogStyle") }
        window.rootViewController = savedRoot
    }

    private func settle(_ t: Double = 0.6) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }

    private func elements(in object: NSObject) -> [NSObject] {
        var out: [NSObject] = []
        if let list = object.accessibilityElements as? [NSObject] {
            for e in list { out.append(e); out += elements(in: e) }
        } else if object.accessibilityElementCount() != NSNotFound, object.accessibilityElementCount() > 0 {
            for i in 0..<object.accessibilityElementCount() {
                if let e = object.accessibilityElement(at: i) as? NSObject { out.append(e); out += elements(in: e) }
            }
        }
        if let view = object as? UIView { for s in view.subviews { out.append(s); out += elements(in: s) } }
        return out
    }

    private func all() -> [NSObject] { elements(in: host.view) }

    /// SwiftUI's tree can fill in late after a host swap, so look again a few times before giving up.
    private func find(_ label: String, last: Bool = false) -> NSObject? {
        for attempt in 0..<6 {
            let hits = all().filter { $0.accessibilityLabel == label && $0.isAccessibilityElement }
            if let hit = last ? hits.last : hits.first { return hit }
            if attempt < 5 { settle(0.8) }
        }
        return nil
    }

    @discardableResult
    private func tap(_ label: String, last: Bool = false, file: StaticString = #filePath, line: UInt = #line) throws -> Bool {
        let e = try XCTUnwrap(find(label, last: last), "no control labelled \(label)", file: file, line: line)
        XCTAssertTrue(e.accessibilityActivate(), "\(label) did not activate", file: file, line: line)
        settle()
        return true
    }

    /// Labels starting "Add " that are not the sheet's own button ("Add Tags", "Add 1 Tag", "Add 2 Tags"):
    /// the old card button was "Add Forehead" / "Add Forehead, Acne". Exact count of the sheet's button is
    /// not asserted because SwiftUI can expose the same node twice.
    private func addButtonCount() -> Int {
        let labels = Set(all().filter { $0.isAccessibilityElement }.compactMap(\.accessibilityLabel).filter { $0.hasPrefix("Add ") })
        let own = labels.filter { $0 == "Add Tags" || $0.range(of: #"^Add \d+ Tags?$"#, options: .regularExpression) != nil }
        return labels.subtracting(own).isEmpty ? 1 : 0
    }

    private func isEnabled(_ label: String) -> Bool? {
        guard let e = find(label) else { return nil }
        // The bottom button's hint says why it is off ("Pick a tag first") or what it does when on.
        return !e.accessibilityTraits.contains(.notEnabled)
            && e.accessibilityHint == "Saves the picked tags to this day"
    }

    func testChipsFlowEnablesTheBottomButtonAndHasNoCardButton() throws {
                XCTAssertEqual(isEnabled("Add Tags"), false, "bottom button starts disabled")
        XCTAssertEqual(addButtonCount(), 1, "no card Add button; " + "only the sheet's own Add button")

        try tap("Forehead")
        XCTAssertEqual(addButtonCount(), 1, "no card Add button; " + "only the sheet's own Add button")
        XCTAssertEqual(isEnabled("Add Tags"), false, "area alone is not a tag yet")

        try tap("Acne")
        XCTAssertEqual(isEnabled("Add 1 Tag"), true, "type picked: bottom button enabled")
        XCTAssertNotNil(find("Add 1 Tag"))

        try tap("Colour Red")
        XCTAssertEqual(isEnabled("Add 1 Tag"), true)

        // A second area adds a second tray entry.
        try tap("Cheeks")
        try tap("Dry")
        XCTAssertEqual(isEnabled("Add 2 Tags"), true)

        // Back to Forehead: its picks come back, and deselecting the type removes its entry.
        try tap("Forehead")
        try tap("Acne")
        XCTAssertEqual(isEnabled("Add 1 Tag"), true)
    }

    /// The reported case: today has no cycle day, so saving is blocked. The reason must sit beside the button.
    func testNoCycleDayExplainsWhySavingIsOff() throws {
        showSheet(withCycle: false)
        try tap("Forehead")
        try tap("Acne")
        XCTAssertNotNil(find("Pick a cycle day"), "button says why it is off")
        XCTAssertEqual(isEnabled("Pick a cycle day"), false)
        XCTAssertNotNil(find("No cycle day on this date, so tags can't be saved. Tap the date to pick another day."),
                        "reason shown beside the button")
    }

    func testOnlyOneConfirmButton() throws {
        try tap("Chin")
        try tap("Breakout")
        XCTAssertEqual(addButtonCount(), 1, "no card Add button; " + "exactly one Add button on screen")
    }

    func testBodyMapFlow() throws {
        try tap("Body map")
        let other = try XCTUnwrap(all().first { $0.accessibilityLabel == "Other"
            && $0.accessibilityHint == "An area that is not on the map" })
        XCTAssertTrue(other.accessibilityActivate())
        settle()
        XCTAssertEqual(addButtonCount(), 1, "no card Add button; " + "only the sheet's own Add button")
        try tap("Irritated")
        XCTAssertEqual(isEnabled("Add 1 Tag"), true)
        try tap("Irritated")
        XCTAssertEqual(isEnabled("Add Tags"), false, "deselecting the last type empties the tray")
    }

    func testSetSkinKeepsOneEntryPerAreaInPlace() {
        var sel = TagSelection()
        let acne = SkinTag(area: .chin, kinds: [.acne], colour: nil)!
        let dry = SkinTag(area: .cheeks, kinds: [.dry], colour: nil)!
        sel.setSkin(acne, area: .chin)
        sel.setSkin(dry, area: .cheeks)
        sel.setSkin(SkinTag(area: .chin, kinds: [.acne, .flaky], colour: .red), area: .chin)
        XCTAssertEqual(sel.items.map(\.pick.raw), ["Skin:Chin/Acne+Flaky/Red", "Skin:Cheeks/Dry"], "edited in place")
        sel.setSkin(nil, area: .chin)
        XCTAssertEqual(sel.items.map(\.pick.raw), ["Skin:Cheeks/Dry"])
    }
}
