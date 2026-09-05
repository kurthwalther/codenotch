import XCTest
@testable import Codenotch

/// "At this pace" has to be honest or it is worse than nothing: these pin
/// when it speaks, when it stays quiet, and what it says.
final class UsagePaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(minutesAgo: Double, used: Double) -> UsagePace.Sample {
        UsagePace.Sample(at: now.addingTimeInterval(-minutesAgo * 60), used: used)
    }

    func testARisingWindowHasAPace() throws {
        let pace = try XCTUnwrap(UsagePace.estimate(from: [
            sample(minutesAgo: 30, used: 0.10),
            sample(minutesAgo: 15, used: 0.15),
            sample(minutesAgo: 0, used: 0.20)
        ], now: now))
        // 10% in 30 minutes.
        XCTAssertEqual(pace.perSecond, 0.10 / (30 * 60), accuracy: 1e-9)
        XCTAssertEqual(pace.timeToEmpty(remaining: 0.80), 4 * 60 * 60, accuracy: 1)
    }

    /// Ten minutes is the least a rate may rest on.
    func testTooShortASpanSaysNothing() {
        XCTAssertNil(UsagePace.estimate(from: [
            sample(minutesAgo: 9, used: 0.10),
            sample(minutesAgo: 0, used: 0.30)
        ], now: now))
    }

    func testAFlatWindowSaysNothing() {
        XCTAssertNil(UsagePace.estimate(from: [
            sample(minutesAgo: 60, used: 0.40),
            sample(minutesAgo: 0, used: 0.40)
        ], now: now))
    }

    /// A drop is the window resetting; readings from before it are another
    /// life of the same window and must not drag the rate down.
    func testReadingsFromBeforeAResetAreIgnored() throws {
        let pace = try XCTUnwrap(UsagePace.estimate(from: [
            sample(minutesAgo: 90, used: 0.80),
            sample(minutesAgo: 60, used: 0.95),
            sample(minutesAgo: 30, used: 0.02),   // reset happened here
            sample(minutesAgo: 0, used: 0.12)
        ], now: now))
        XCTAssertEqual(pace.perSecond, 0.10 / (30 * 60), accuracy: 1e-9)
    }

    func testOnlyTheLookbackCounts() throws {
        let pace = try XCTUnwrap(UsagePace.estimate(from: [
            sample(minutesAgo: 600, used: 0.0),    // ten hours ago: out of the window
            sample(minutesAgo: 60, used: 0.30),
            sample(minutesAgo: 0, used: 0.40)
        ], now: now))
        XCTAssertEqual(pace.perSecond, 0.10 / (60 * 60), accuracy: 1e-9)
    }

    func testItSaysWhenItRunsOutBeforeTheReset() {
        let pace = UsagePace(perSecond: 0.10 / (30 * 60))   // 20% an hour
        let reset = now.addingTimeInterval(5 * 60 * 60)
        XCTAssertEqual(pace.text(remaining: 0.30, resetsAt: reset, now: now), "Out in 1 hr 30 min")
    }

    func testItReassuresWhenTheResetComesFirst() {
        let pace = UsagePace(perSecond: 0.10 / (30 * 60))
        let reset = now.addingTimeInterval(60 * 60)
        XCTAssertEqual(pace.text(remaining: 0.30, resetsAt: reset, now: now), "Lasts until reset")
    }

    func testNothingLeftIsNotAForecast() {
        let pace = UsagePace(perSecond: 0.01)
        XCTAssertNil(pace.text(remaining: 0, resetsAt: nil, now: now))
    }

    func testSpansReadAsPeopleSayThem() {
        XCTAssertEqual(ElapsedCopy.span(30), "1 min")
        XCTAssertEqual(ElapsedCopy.span(45 * 60), "45 min")
        XCTAssertEqual(ElapsedCopy.span(2 * 3600), "2 hr")
        XCTAssertEqual(ElapsedCopy.span(2 * 3600 + 5 * 60), "2 hr 5 min")
        XCTAssertEqual(ElapsedCopy.span(30 * 3600), "1 day 6 hr")
        XCTAssertEqual(ElapsedCopy.span(3 * 24 * 3600 + 5 * 3600), "3 days")
    }

    /// The history feeds the pace: readings go in per window, and the
    /// snapshot comes back with a pace for the windows that earned one.
    func testHistoryRecordsAndAttachesAPace() {
        let name = "history-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let history = UsageHistory(defaults: defaults)

        func snapshot(_ used: Double) -> ProviderSnapshot {
            ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
                             fidelity: .official, status: .ok,
                             windows: [LimitWindow(id: "session", label: "Session", usedFraction: used),
                                       LimitWindow(id: "count", label: "Count", remaining: 3)])
        }
        history.record(snapshot(0.10), at: now.addingTimeInterval(-20 * 60))
        history.record(snapshot(0.20), at: now)

        let paced = history.attachingPace(to: snapshot(0.20), now: now)
        XCTAssertNotNil(paced.pace["session"])
        XCTAssertNil(paced.pace["count"], "a window without a denominator has no pace")

        history.forget("claude")
        XCTAssertTrue(history.samples(providerID: "claude", windowID: "session").isEmpty)
    }
}
