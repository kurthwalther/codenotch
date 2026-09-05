import XCTest
import SwiftUI
@testable import Codenotch

/// The tail is written once, pointing right, and turned onto the other three
/// directions. These pin the turn — the tip lands on the side the direction
/// names and the base sits flush against the card opposite — and the curve
/// itself, which has to leave the card tangentially rather than at an angle.
@MainActor
final class TooltipTailTests: XCTestCase {
    private func rect(_ direction: NotchEdge.TooltipDirection) -> CGRect {
        CGRect(origin: .zero, size: TooltipTail.size(for: direction))
    }

    private func contains(_ direction: NotchEdge.TooltipDirection, _ point: CGPoint) -> Bool {
        TooltipTail(direction: direction).path(in: rect(direction)).contains(point)
    }

    func testTheTipPointsTheWayTheDirectionSays() {
        let inset: CGFloat = 1
        let side = rect(.leading)
        XCTAssertTrue(contains(.leading, CGPoint(x: side.maxX - inset, y: side.midY)))
        XCTAssertTrue(contains(.trailing, CGPoint(x: side.minX + inset, y: side.midY)))
        let stacked = rect(.down)
        XCTAssertTrue(contains(.down, CGPoint(x: stacked.midX, y: stacked.minY + inset)))
        XCTAssertTrue(contains(.up, CGPoint(x: stacked.midX, y: stacked.maxY - inset)))
    }

    func testTheEdgesLeaveTheCardTangentially() {
        let r = rect(.leading)
        // Just inside the base, near both corners: the fillet hugs the card at
        // first, so the tail is still nearly full-height there.
        XCTAssertTrue(contains(.leading, CGPoint(x: 0.5, y: 2)))
        XCTAssertTrue(contains(.leading, CGPoint(x: 0.5, y: r.maxY - 2)))
        // A quarter of the way out, the edge has bowed in past where a
        // straight one would run: these points sit inside the triangle this
        // replaced, and outside the curve.
        XCTAssertFalse(contains(.leading, CGPoint(x: r.maxX * 0.25, y: r.maxY * 0.15)))
        XCTAssertFalse(contains(.leading, CGPoint(x: r.maxX * 0.25, y: r.maxY * 0.85)))
    }

    func testTheShapeStaysInsideItsFrame() {
        for direction: NotchEdge.TooltipDirection in [.leading, .trailing, .up, .down] {
            let frame = rect(direction)
            let bounds = TooltipTail(direction: direction).path(in: frame).boundingRect
            XCTAssertTrue(frame.insetBy(dx: -0.01, dy: -0.01).contains(bounds),
                          "\(direction): \(bounds) spills out of \(frame)")
        }
    }

    /// A look at it: set `TOOLTIP_TAIL_RENDER_PATH` and a card is drawn facing
    /// each way, black on light, so the silhouette is what you see.
    func testRendersEveryDirection() throws {
        let now = Date()
        let snapshot = ProviderSnapshot(
            id: "claude", displayName: "Claude", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [
                LimitWindow(id: "session", label: "Current session", usedFraction: 0.23,
                            resetsAt: now.addingTimeInterval(3 * 3600)),
                LimitWindow(id: "all", label: "All models", usedFraction: 0.80,
                            resetsAt: now.addingTimeInterval(30 * 3600))
            ]
        )
        let view = HStack(alignment: .center, spacing: 40) {
            TooltipCard(snapshot: snapshot, now: now, direction: .leading)
            TooltipCard(snapshot: snapshot, now: now, direction: .trailing)
            VStack(spacing: 40) {
                TooltipCard(snapshot: snapshot, now: now, direction: .up)
                TooltipCard(snapshot: snapshot, now: now, direction: .down)
            }
        }
        .padding(40)
        .background(Color(white: 0.92))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, NotchLayout.cardWidth * 2)

        if let path = ProcessInfo.processInfo.environment["TOOLTIP_TAIL_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
