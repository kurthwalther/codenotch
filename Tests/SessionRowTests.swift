import XCTest
@testable import Codenotch

/// The rows a click can land on: where the card puts them, and in what order.
final class SessionRowTests: XCTestCase {
    private func session(_ name: String, _ state: AgentSession.State, minutesAgo: Double,
                         locator: SessionLocator? = nil) -> AgentSession {
        AgentSession(id: name, name: name, detail: "Terminal", state: state, waitingFor: nil,
                     since: Date().addingTimeInterval(-minutesAgo * 60), locator: locator)
    }

    func testRowsSitBetweenTheRuleAndTheFootOfTheCard() {
        let ranges = NotchLayout.sessionRowRanges(windowCount: 3, sessionCount: 2, sessionCap: 4)
        let height = NotchLayout.cardHeight(windowCount: 3, sessionCount: 2, sessionCap: 4)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertLessThan(ranges[0].upperBound, ranges[1].lowerBound, "rows do not overlap")
        XCTAssertLessThanOrEqual(ranges[1].upperBound, height - NotchLayout.cardPadding + 0.001,
                                 "the last row ends at the card's padding")
        // The gap between rows is the card's block spacing, exactly.
        XCTAssertEqual(ranges[1].lowerBound - ranges[0].upperBound, NotchLayout.blockSpacing, accuracy: 0.001)
    }

    func testOnlyTheListedRowsCount() {
        XCTAssertEqual(NotchLayout.sessionRowRanges(windowCount: 2, sessionCount: 9, sessionCap: 4).count, 4)
        XCTAssertTrue(NotchLayout.sessionRowRanges(windowCount: 2, sessionCount: 0).isEmpty)
    }

    /// With a status message instead of windows, the rows move with it.
    func testRowsFollowAStatusMessage() {
        let short = NotchLayout.sessionRowRanges(windowCount: 0, sessionCount: 1, statusMessage: "Waiting…")
        let long = NotchLayout.sessionRowRanges(windowCount: 0, sessionCount: 1,
                                                statusMessage: String(repeating: "a long message ", count: 12))
        XCTAssertGreaterThan(long[0].lowerBound, short[0].lowerBound)
    }

    func testTheListIsOrderedWaitingBusyIdleNewestFirst() throws {
        let summary = try XCTUnwrap(ActivitySummary(sessions: [
            session("old-idle", .idle, minutesAgo: 50),
            session("busy", .busy, minutesAgo: 5),
            session("new-idle", .idle, minutesAgo: 1),
            session("waiting", .waiting, minutesAgo: 30)
        ]))
        XCTAssertEqual(summary.ordered.map(\.name), ["waiting", "busy", "new-idle", "old-idle"])
    }

    func testTheLocatorRidesAlongWithTheSession() {
        let s = session("s", .busy, minutesAgo: 0, locator: SessionLocator(pid: 42, cwd: "/tmp"))
        XCTAssertEqual(s.locator?.pid, 42)
        XCTAssertNil(session("t", .busy, minutesAgo: 0).locator)
    }
}
