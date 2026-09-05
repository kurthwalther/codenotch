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
        XCTAssertEqual(s.secondaryReading?.band, .ample)
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
        first.secondaryStyle = .bar
        first.notchScale = 0.7

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.secondaryWindow(for: "claude"), "weekly_scoped")
        XCTAssertEqual(second.secondaryStyle, .bar)
        XCTAssertEqual(second.notchScale, 0.7, accuracy: 0.0001)
    }

    func testTheNotchIsSmallerThanTheFrameByDefault() {
        let name = "scale-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertEqual(Preferences(defaults: defaults).notchScale, 0.8, accuracy: 0.0001)
    }

    /// The bar style claims its height from every cell, so the stack keeps
    /// one pitch and the hover bands keep lining up with the rings.
    func testTheBarStyleReservesRoomInEveryCell() {
        let before = NotchLayout.cellExtent
        NotchLayout.reservesSecondaryBar = true
        defer { NotchLayout.reservesSecondaryBar = false }
        XCTAssertEqual(NotchLayout.cellExtent - before, NotchLayout.secondaryBarHeight, accuracy: 0.001)
        XCTAssertEqual(NotchLayout.bodyDepth(for: .top) - NotchLayout.bodyDepth(for: .right),
                       NotchLayout.cellExtent - NotchLayout.sideBodyDepth + 2 * ((NotchLayout.sideBodyDepth - NotchLayout.ringDiameter) / 2),
                       accuracy: 0.001, "a horizontal notch grows by the same bar")
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
