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

    /// The notice as it arrives: the card goes to the agent's window, the
    /// glyph opens the conversation. Set `NOTICE_RENDER_PATH`.
    func testTheNoticeCardRenders() throws {
        func notice(_ kind: SessionNotice.Kind, _ name: String, _ detail: String,
                    _ preview: String) -> SessionNotice {
            SessionNotice(
                id: name,
                session: AgentSession(id: name, name: name, detail: detail,
                                      state: kind == .waiting ? .waiting : .idle,
                                      waitingFor: nil, since: Date()),
                kind: kind, preview: preview, at: Date()
            )
        }
        let view = VStack(spacing: Design.px(10)) {
            NoticeCardView(
                notice: notice(.finished, "codenotch", "Terminal",
                               "Tests pass, 589 green. Installed and pushed."),
                focus: {}, open: {})
            NoticeCardView(
                notice: notice(.waiting, "site", "iTerm",
                               "Run the migration against production?"),
                focus: {}, open: {}, answer: { _ in })
        }
        .padding(30)
        .background(Palette.notch)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, 0)
        if let path = ProcessInfo.processInfo.environment["NOTICE_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    func testTheResetLineRendersAtNotchScale() throws {
        Design.notchFactor = 0.8
        defer { Design.notchFactor = 1 }

        let view = HStack(alignment: .top, spacing: 34) {
            cell("Claude", 0.23, hours: 2.17)
            cell("Codex", 0.52, hours: 0.75)
            cell("Cursor", 0.73, hours: 76)
            cell("Spent", 1.0, hours: 2.17)
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
