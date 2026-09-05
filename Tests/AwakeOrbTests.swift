import XCTest
@testable import Codenotch

/// The keep-awake handle is the settings handle reflected to the other end
/// of the stack. These pin the reflection on every edge, with and without a
/// hardware notch to hug, and that the two never answer the same point.
@MainActor
final class AwakeOrbTests: XCTestCase {
    private func model(edge: NotchEdge, cells: Int = 2,
                       hardware: HardwareNotch? = nil) -> NotchViewModel {
        let m = NotchViewModel()
        m.edge = edge
        m.hardwareNotch = hardware
        m.snapshots = (0..<cells).map {
            ProviderSnapshot(id: "p\($0)", displayName: "P", glyph: .claude,
                             fidelity: .official, status: .ok,
                             windows: [LimitWindow(id: "w", label: "W", usedFraction: 0.3)])
        }
        m.isExpanded = true
        return m
    }

    func testItSitsAtTheOtherEndTheSameDistanceIn() {
        for edge in NotchEdge.allCases {
            let m = model(edge: edge)
            XCTAssertEqual(m.awakeAlong + m.orbAlong, m.shapeLength, accuracy: 0.001,
                           "\(edge): not the mirror image along the stack")
            XCTAssertEqual(m.awakeArcOffset, .zero, "\(edge): nestled in a flare, the arc is the orb")
        }
    }

    func testTheTwoHandlesNeverOverlap() {
        for edge in NotchEdge.allCases {
            let m = model(edge: edge, cells: 1)
            let awake = m.awakeHandlePoints[0]
            let settings = m.orbHandlePoints[0]
            XCTAssertTrue(m.isOnAwakeHandle(along: awake.x, across: awake.y))
            XCTAssertFalse(m.isOnOrbHandle(along: awake.x, across: awake.y), "\(edge)")
            XCTAssertTrue(m.isOnOrbHandle(along: settings.x, across: settings.y))
            XCTAssertFalse(m.isOnAwakeHandle(along: settings.x, across: settings.y), "\(edge)")
        }
    }

    /// The resting arc faces outward and *forward* along the stack: a quarter
    /// circle, sharing the outward half with the settings arc and reflecting
    /// the other.
    func testTheRestingArcFacesTheNotch() {
        for edge in NotchEdge.allCases {
            let far = SettingsOrb.restingTrim(for: edge)
            let near = SettingsOrb.restingTrim(for: edge, atStart: true)
            XCTAssertEqual(near.upperBound - near.lowerBound, 0.25, accuracy: 0.001)
            XCTAssertNotEqual(near, far, "\(edge): the two arcs face the same way")
        }
        XCTAssertEqual(SettingsOrb.restingTrim(for: .right, atStart: true), 0.0...0.25)
        XCTAssertEqual(SettingsOrb.restingTrim(for: .top, atStart: true), 0.75...1.0)
    }

    /// Hugging a corner from outside, the offset that carries the settings arc
    /// back onto its corner is reflected along the stack for this one.
    func testOnAFlushBarTheArcOffsetIsReflected() {
        let hardware = HardwareNotch(width: 220, height: 32)
        let m = model(edge: .top, hardware: hardware)
        guard m.orbHugsCorner else { return }
        // Along the stack (x, on the top edge) the two go opposite ways;
        // inward (y) they agree.
        XCTAssertEqual(m.awakeArcOffset.width, -m.orbArcOffset.width, accuracy: 0.001)
        XCTAssertEqual(m.awakeArcOffset.height, m.orbArcOffset.height, accuracy: 0.001)
    }

    /// Caffeine's convention — a full cup on, an empty one off — with the
    /// colour saying it again and the caption spelling out the case the cup
    /// cannot: on, but with nothing running.
    func testTheCupAndTheCaptionSayWhatIsHappening() {
        let m = NotchViewModel()
        m.keepAwakeMode = .off
        XCTAssertEqual(m.awakeSymbol, "cup.and.saucer")
        XCTAssertEqual(m.awakeCaption, "Off")
        XCTAssertFalse(m.awakeDim)
        XCTAssertFalse(m.awakeGlows)

        m.keepAwakeMode = .whileWorking
        XCTAssertEqual(m.awakeSymbol, "cup.and.saucer.fill")
        XCTAssertEqual(m.awakeCaption, "No agents running")
        XCTAssertTrue(m.awakeDim, "on with nothing to hold is shown faded")

        m.isHoldingAwake = true
        XCTAssertEqual(m.awakeCaption, "Keeping awake")
        XCTAssertFalse(m.awakeDim)
        XCTAssertFalse(m.awakeGlows, "only the steaming cup glows")

        m.keepAwakeMode = .whileOpen
        XCTAssertEqual(m.awakeSymbol, "cup.and.heat.waves.fill")
        XCTAssertTrue(m.awakeGlows)
        m.isHoldingAwake = false
        XCTAssertEqual(m.awakeCaption, "No sessions open", "while open, it is sessions that are missing")
        XCTAssertFalse(m.awakeGlows)
    }
}
