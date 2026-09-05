import XCTest
@testable import Codenotch

/// A second window in the cell: which one it is, what the cell draws for it,
/// and the room the bar style claims from every cell.
@MainActor
final class SecondaryWindowTests: XCTestCase {
    private func window(_ id: String, _ used: Double) -> LimitWindow {
        LimitWindow(id: id, label: id, usedFraction: used)
    }

    private func snapshot(_ windows: [LimitWindow]) -> ProviderSnapshot {
        ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
                         fidelity: .official, status: .ok, windows: windows)
    }

    func testTheSecondWindowIsTheChosenOne() {
        let s = snapshot([window("session", 0.3), window("weekly_scoped", 0.42)])
            .choosingSecondary("weekly_scoped")
        XCTAssertEqual(s.secondary?.id, "weekly_scoped")
        XCTAssertEqual(s.secondaryReading?.remaining ?? -1, 0.58, accuracy: 0.0001)
        XCTAssertEqual(s.secondaryReading?.band(.standard), .ample)
    }

    /// It cannot be the ring's own window — that is one gauge shown twice.
    func testTheRingsOwnWindowIsNotASecondOne() {
        let s = snapshot([window("session", 0.3), window("weekly_scoped", 0.42)])
            .choosingHeadline("weekly_scoped").choosingSecondary("weekly_scoped")
        XCTAssertNil(s.secondary)
    }

    func testAMissingOrAbsentChoiceShowsNothing() {
        let s = snapshot([window("session", 0.3)])
        XCTAssertNil(s.choosingSecondary("weekly_all").secondary)
        XCTAssertNil(s.choosingSecondary(nil).secondary)
    }

    func testTheChoicesAreRemembered() {
        let name = "secondary-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let first = Preferences(defaults: defaults)
        first.setSecondaryWindow("weekly_scoped", for: "claude")
        first.notchScale = 0.7

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.secondaryWindow(for: "claude"), "weekly_scoped")
        XCTAssertEqual(second.notchScale, 0.7, accuracy: 0.0001)
    }

    func testTheNotchIsSmallerThanTheFrameByDefault() {
        let name = "scale-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertEqual(Preferences(defaults: defaults).notchScale, 0.8, accuracy: 0.0001)
    }

    /// The bar claims its room from every cell, so the stack keeps one pitch
    /// and the hover bands keep lining up with the rings — which have moved
    /// along by the bar, since it sits above them.
    func testTheBarReservesRoomInEveryCellAboveTheRing() {
        let extent = NotchLayout.cellExtent
        let ring = NotchLayout.ringCenter(index: 0, edge: .right)
        let acrossRing = NotchLayout.ringCenter(index: 0, edge: .top)
        let depth = NotchLayout.bodyDepth(for: .top)
        NotchLayout.reservesSecondaryBar = true
        defer { NotchLayout.reservesSecondaryBar = false }

        let space = NotchLayout.secondaryBarHeight + NotchLayout.secondaryBarLabelGap
            + NotchLayout.secondaryBarLabelHeight + NotchLayout.secondaryBarGap
        XCTAssertEqual(NotchLayout.cellExtent - extent, space, accuracy: 0.001)
        XCTAssertEqual(NotchLayout.ringCenter(index: 0, edge: .right) - ring, space, accuracy: 0.001,
                       "down a side edge the ring follows the bar")
        XCTAssertEqual(NotchLayout.ringCenter(index: 0, edge: .top), acrossRing, accuracy: 0.001,
                       "across a horizontal edge the bar is in the depth, not along the stack")
        XCTAssertEqual(NotchLayout.bodyDepth(for: .top) - depth, space, accuracy: 0.001,
                       "and the depth grows by it instead")
        XCTAssertEqual(NotchLayout.bodyDepth(for: .right), NotchLayout.sideBodyDepth, accuracy: 0.001,
                       "a side notch keeps the frame's depth")
    }

    /// The notch's own scale moves every notch measurement and none of the
    /// card's.
    func testTheNotchScaleLeavesTheCardAlone() {
        let ring = NotchLayout.ringDiameter, card = NotchLayout.cardWidth
        let tail = NotchLayout.tailLength, depth = NotchLayout.sideBodyDepth
        Design.notchFactor = 0.8
        defer { Design.notchFactor = 1 }
        XCTAssertEqual(NotchLayout.ringDiameter, ring * 0.8, accuracy: 0.001)
        XCTAssertEqual(NotchLayout.sideBodyDepth, depth * 0.8, accuracy: 0.001)
        XCTAssertEqual(NotchLayout.cardWidth, card, accuracy: 0.001)
        XCTAssertEqual(NotchLayout.tailLength, tail, accuracy: 0.001)
        XCTAssertLessThan(NotchLayout.percentLineHeight, NotchLayout.cardTitleLineHeight,
                          "the percent has shrunk with the notch; the card's title has not")
    }
}
