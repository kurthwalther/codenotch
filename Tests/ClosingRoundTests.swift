import XCTest
import SwiftUI
@testable import Codenotch

/// The last round: movable colour thresholds, a number that counts down to
/// the reset, and the resting state's arithmetic.
@MainActor
final class ClosingRoundTests: XCTestCase {
    private func scratch() -> UserDefaults {
        let name = "closing-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Thresholds

    func testTheStandardThresholdsAreTheFramesOwn() {
        XCTAssertEqual(UsageBand.band(for: 0.4999), .ample)
        XCTAssertEqual(UsageBand.band(for: 0.50), .watch)
        XCTAssertEqual(UsageBand.band(for: 0.70), .critical, "the floating-point whisker is absorbed")
        XCTAssertEqual(UsageBand.band(for: 1.0), .exhausted)
    }

    func testMovedThresholdsMoveTheColours() {
        // Red at 40% left, yellow at 60%.
        let early = UsageThresholds(watchBelowLeft: 0.6, criticalBelowLeft: 0.4)
        XCTAssertEqual(UsageBand.band(for: 0.35, thresholds: early), .ample)
        XCTAssertEqual(UsageBand.band(for: 0.45, thresholds: early), .watch)
        XCTAssertEqual(UsageBand.band(for: 0.65, thresholds: early), .critical)
        XCTAssertEqual(UsageBand.band(for: 1.2, thresholds: early), .exhausted)
    }

    func testRedIsKeptBelowYellow() {
        let crossed = UsageThresholds(watchBelowLeft: 0.2, criticalBelowLeft: 0.5).ordered
        XCTAssertEqual(crossed.watchBelowLeft, 0.5, accuracy: 0.0001)
        XCTAssertEqual(crossed.criticalBelowLeft, 0.2, accuracy: 0.0001)
    }

    func testThresholdsAreRemembered() {
        let defaults = scratch()
        let first = Preferences(defaults: defaults)
        XCTAssertEqual(first.thresholds, .standard)
        first.thresholds = UsageThresholds(watchBelowLeft: 0.6, criticalBelowLeft: 0.4)
        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.thresholds.watchBelowLeft, 0.6, accuracy: 0.0001)
        XCTAssertEqual(second.thresholds.criticalBelowLeft, 0.4, accuracy: 0.0001)
    }

    // MARK: The number under the ring

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(resetsIn seconds: TimeInterval?) -> ProviderSnapshot {
        ProviderSnapshot(id: "claude", displayName: "Claude", glyph: .claude,
                         fidelity: .official, status: .ok,
                         windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.23,
                                               resetsAt: seconds.map { now.addingTimeInterval($0) })])
    }

    func testTheNumberCanCountDownToTheReset() {
        let s = snapshot(resetsIn: 2 * 3600 + 10 * 60)
        XCTAssertEqual(s.cellText(now: now), "77%")
        XCTAssertEqual(s.choosingLabel(.timeToReset).cellText(now: now), "2h 10m")
        XCTAssertEqual(snapshot(resetsIn: 45 * 60).choosingLabel(.timeToReset).cellText(now: now), "45m")
        XCTAssertEqual(snapshot(resetsIn: 3 * 86400 + 4 * 3600).choosingLabel(.timeToReset).cellText(now: now), "3d 4h")
        XCTAssertEqual(snapshot(resetsIn: -5).choosingLabel(.timeToReset).cellText(now: now), "now")
    }

    /// A provider that never says when it resets keeps the percentage,
    /// whatever was asked for.
    func testWithoutAResetTheNumberStaysAPercentage() {
        XCTAssertEqual(snapshot(resetsIn: nil).choosingLabel(.timeToReset).cellText(now: now), "77%")
    }

    func testTheLabelChoiceIsRememberedPerProvider() {
        let defaults = scratch()
        let first = Preferences(defaults: defaults)
        XCTAssertEqual(first.cellLabel(for: "claude"), .percentLeft)
        first.setCellLabel(.timeToReset, for: "claude")
        XCTAssertEqual(Preferences(defaults: defaults).cellLabel(for: "claude"), .timeToReset)
        first.setCellLabel(.percentLeft, for: "claude")
        XCTAssertNil(first.cellLabels["claude"], "the default is not stored")
    }

    func testCompactSpans() {
        XCTAssertEqual(ElapsedCopy.compact(30), "1m")
        XCTAssertEqual(ElapsedCopy.compact(2 * 3600), "2h")
        XCTAssertEqual(ElapsedCopy.compact(26 * 3600), "1d 2h")
    }

    // MARK: Resting

    func testRestingIsSmallerAndQuieterButNeverGone() {
        XCTAssertEqual(NotchViewModel.restingScale, 0.8, accuracy: 0.0001)
        XCTAssertEqual(NotchViewModel.restingOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(NotchWindowController.restAfter, 10, accuracy: 0.0001)
    }

    /// A rendered cell at rest, for a look: set `REST_RENDER_PATH`.
    func testARestingCellRenders() throws {
        let busy = ActivitySummary(sessions: [
            AgentSession(id: "s", name: "s", detail: "Terminal", state: .busy, waitingFor: nil, since: Date())
        ])
        let s = snapshot(resetsIn: 3600)
        let view = HStack(spacing: 40) {
            ProviderCell(snapshot: s, activity: busy, now: now)
            ProviderCell(snapshot: s, activity: busy, isResting: true, now: now)
                .opacity(NotchViewModel.restingOpacity)
                .scaleEffect(NotchViewModel.restingScale)
            ProviderCell(snapshot: s.choosingLabel(.timeToReset), activity: busy, now: now)
        }
        .padding(30)
        .background(Palette.notch)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, NotchLayout.ringDiameter * 3)
        if let path = ProcessInfo.processInfo.environment["REST_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
