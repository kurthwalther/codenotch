import XCTest
@testable import Codenotch

/// What decides whether the Mac is held awake. The decision is pure, so it can
/// be pinned without taking a real power assertion for every case.
@MainActor
final class KeepAwakeTests: XCTestCase {
    private func session(_ state: AgentSession.State) -> AgentSession {
        AgentSession(id: UUID().uuidString, name: "s", detail: "Terminal",
                     state: state, waitingFor: nil, since: Date())
    }

    func testNothingIsHeldWhileEverythingIsIdle() {
        XCTAssertNil(KeepAwake.wanted(enabled: true, display: false,
                                      sessions: ["claude": [session(.idle)]]))
        XCTAssertNil(KeepAwake.wanted(enabled: true, display: false, sessions: [:]))
    }

    func testOneBusySessionAnywhereHoldsTheMac() {
        XCTAssertEqual(
            KeepAwake.wanted(enabled: true, display: false,
                             sessions: ["claude": [session(.idle)], "codex": [session(.busy)]]),
            .system
        )
    }

    /// Waiting is not working: the agent is blocked on you, and nothing is lost
    /// by the Mac sleeping until you come back.
    func testWaitingDoesNotHoldTheMac() {
        XCTAssertNil(KeepAwake.wanted(enabled: true, display: false,
                                      sessions: ["claude": [session(.waiting)]]))
    }

    func testTheDisplayIsOnlyHeldWhenAsked() {
        XCTAssertEqual(
            KeepAwake.wanted(enabled: true, display: true, sessions: ["claude": [session(.busy)]]),
            .display
        )
    }

    /// While open, a session waiting on you — or merely idle — holds the Mac:
    /// that is the remote case, where the agent spends its time waiting.
    func testWhileOpenAnySessionHoldsTheMac() {
        XCTAssertEqual(
            KeepAwake.wanted(enabled: true, display: false, scope: .whileOpen,
                             sessions: ["claude": [session(.waiting)]]),
            .system
        )
        XCTAssertEqual(
            KeepAwake.wanted(enabled: true, display: false, scope: .whileOpen,
                             sessions: ["claude": [session(.idle)]]),
            .system
        )
        XCTAssertNil(KeepAwake.wanted(enabled: true, display: false, scope: .whileOpen,
                                      sessions: ["claude": []]),
                     "no session at all, and the Mac may sleep")
    }

    func testSwitchedOffHoldsNothing() {
        XCTAssertNil(KeepAwake.wanted(enabled: false, display: true,
                                      sessions: ["claude": [session(.busy)]]))
    }

    /// The real thing, briefly: an assertion is taken, swapped and released.
    func testHoldingSwappingAndReleasingARealAssertion() {
        let keepAwake = KeepAwake()
        keepAwake.hold(.system)
        XCTAssertEqual(keepAwake.held, .system)
        keepAwake.hold(.system)
        XCTAssertEqual(keepAwake.held, .system, "holding what is already held is a no-op")
        keepAwake.hold(.display)
        XCTAssertEqual(keepAwake.held, .display)
        keepAwake.hold(nil)
        XCTAssertNil(keepAwake.held)
    }
}
