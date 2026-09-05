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

    /// A second window's bar above the ring, beside a cell holding the slot
    /// empty, with a busy session so the activity arc is in the picture. Set
    /// `RING_BAR_RENDER_PATH` and the frame is written there.
    func testTheSecondWindowLaysOutAboveTheRing() throws {
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
        let low = ProviderSnapshot(
            id: "claude-low", displayName: "Claude", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.30),
                      LimitWindow(id: "weekly_scoped", label: "Fable", usedFraction: 0.85)],
            headlineID: "session", secondaryID: "weekly_scoped"
        )
        let view = HStack(alignment: .top, spacing: 40) {
            ProviderCell(snapshot: snapshot, activity: busy, reservesBar: true)
            ProviderCell(snapshot: low, reservesBar: true)
            ProviderCell(snapshot: plain, reservesBar: true)
        }
        .padding(30)
        .background(Palette.notch)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, NotchLayout.ringDiameter * 3)

        if let path = ProcessInfo.processInfo.environment["RING_BAR_RENDER_PATH"] {
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
