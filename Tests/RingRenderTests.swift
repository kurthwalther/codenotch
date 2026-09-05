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
