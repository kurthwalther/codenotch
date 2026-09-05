import XCTest
import SwiftUI
@testable import Codenotch

/// Renders a row of provider cells at the levels that matter — plenty left,
/// getting low, nothing left, blocked — so the ring can be looked at without
/// launching the app. Set `RING_RENDER_PATH` and the frame is written there.
@MainActor
final class RingRenderTests: XCTestCase {
    private func cell(_ used: Double, blocked: Bool = false) -> ProviderCell {
        var snapshot = ProviderSnapshot(
            id: "claude-\(used)", displayName: "Claude", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: used)]
        )
        if blocked { snapshot.block = UsageBlock(reason: "Paused", resetsAt: nil) }
        return ProviderCell(snapshot: snapshot)
    }

    /// The three ways of drawing a second window, side by side, each with a
    /// busy session so the activity arc's fit can be judged too. Set
    /// `RING_STYLES_RENDER_PATH` and the frame is written there.
    func testTheSecondWindowLaysOutInEveryStyle() throws {
        var snapshot = ProviderSnapshot(
            id: "claude", displayName: "Claude", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.30),
                      LimitWindow(id: "weekly_scoped", label: "Fable", usedFraction: 0.42)],
            headlineID: "session", secondaryID: "weekly_scoped"
        )
        let busy = ActivitySummary(sessions: [
            AgentSession(id: "s", name: "s", detail: "Terminal", state: .busy, waitingFor: nil, since: Date())
        ])
        var plain = snapshot
        plain.secondaryID = nil
        snapshot.secondaryID = "weekly_scoped"

        NotchLayout.reservesSecondaryBar = true
        defer { NotchLayout.reservesSecondaryBar = false }
        let view = HStack(alignment: .top, spacing: 40) {
            ForEach(SecondaryStyle.allCases) { style in
                VStack(spacing: 24) {
                    ProviderCell(snapshot: snapshot, activity: busy, secondaryStyle: style)
                    ProviderCell(snapshot: plain, secondaryStyle: style)
                }
            }
        }
        .padding(30)
        .background(Palette.notch)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, NotchLayout.ringDiameter * 3)

        if let path = ProcessInfo.processInfo.environment["RING_STYLES_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    func testTheRingLaysOutAtEveryLevel() throws {
        let view = HStack(spacing: 30) {
            cell(0.0); cell(0.23); cell(0.52); cell(0.73); cell(1.0); cell(0.16, blocked: true)
        }
        .padding(30)
        .background(Palette.notch)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, NotchLayout.ringDiameter * 6)

        if let path = ProcessInfo.processInfo.environment["RING_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
