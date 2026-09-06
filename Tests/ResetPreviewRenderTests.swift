import XCTest
import SwiftUI
@testable import Codenotch

/// Draws the line under the number at the notch's real scale, so the size can
/// be judged without launching the app. Set `RESET_RENDER_PATH`.
@MainActor
final class ResetPreviewRenderTests: XCTestCase {
    private func cell(_ name: String, _ used: Double, hours: Double,
                      label: CellLabel = .percentLeft) -> ProviderCell {
        var snapshot = ProviderSnapshot(
            id: name, displayName: name, glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: used,
                                  resetsAt: Date().addingTimeInterval(hours * 3600))]
        )
        snapshot.cellLabel = label
        return ProviderCell(snapshot: snapshot)
    }

    func testTheResetLineRendersAtNotchScale() throws {
        Design.notchFactor = 0.8
        defer { Design.notchFactor = 1 }

        let view = HStack(alignment: .top, spacing: 34) {
            cell("Claude", 0.23, hours: 2.17)
            cell("Codex", 0.52, hours: 0.75)
            cell("Cursor", 0.73, hours: 76)
            cell("Fable", 0.16, hours: 2.17, label: .timeToReset)
        }
        .padding(30)
        .background(Palette.notch)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, 0)

        if let path = ProcessInfo.processInfo.environment["RESET_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
