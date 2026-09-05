import XCTest
import SwiftUI
@testable import Codenotch

/// The tail is written once, pointing right, and turned onto the other three
/// directions. These pin the turn — the apex lands on the side the direction
/// names and the base sits flush against the card opposite — and the profile
/// itself: a swell that overhangs the frame along the card and closes in a
/// dome, with no point.
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

    /// The width of the swell at a given distance along it, found by walking
    /// in from the frame's top until the shape starts.
    private func halfWidth(at fraction: CGFloat) -> CGFloat {
        let r = rect(.leading)
        let x = r.maxX * fraction
        var y = r.minY - r.height
        while y < r.midY, !contains(.leading, CGPoint(x: x, y: y)) { y += 0.25 }
        return r.midY - y
    }

    func testTheSwellOverhangsTheFrameAlongTheCard() {
        let r = rect(.leading)
        let overhang = TooltipTail.shoulder * r.height
        // Right at the card, the swell reaches past both corners of the frame…
        XCTAssertTrue(contains(.leading, CGPoint(x: 0.5, y: -overhang * 0.5)))
        XCTAssertTrue(contains(.leading, CGPoint(x: 0.5, y: r.maxY + overhang * 0.5)))
        // …and no further than the shoulder says.
        XCTAssertFalse(contains(.leading, CGPoint(x: 0.5, y: -overhang - 1)))
        XCTAssertFalse(contains(.leading, CGPoint(x: 0.5, y: r.maxY + overhang + 1)))
    }

    func testTheSwellNarrowsToADomeWithNoPoint() {
        // Monotonically narrower toward the apex.
        let widths = stride(from: CGFloat(0.1), through: 0.9, by: 0.2).map(halfWidth(at:))
        for (near, far) in zip(widths, widths.dropFirst()) {
            XCTAssertGreaterThan(near, far)
        }
        // A dome, not a point: still some width a little short of the apex.
        XCTAssertGreaterThan(halfWidth(at: 0.9), 1)
    }

    func testTheShapeStaysWithinItsLength() {
        for direction: NotchEdge.TooltipDirection in [.leading, .trailing, .up, .down] {
            let frame = rect(direction)
            let bounds = TooltipTail(direction: direction).path(in: frame).boundingRect
            let spill = frame.insetBy(dx: -0.01, dy: -0.01)
            // Along the tail it keeps to its frame — the panel's geometry is
            // built on that length — while across it the shoulders overhang.
            switch direction {
            case .leading, .trailing:
                XCTAssertGreaterThanOrEqual(bounds.minX, spill.minX, "\(direction)")
                XCTAssertLessThanOrEqual(bounds.maxX, spill.maxX, "\(direction)")
                XCTAssertLessThan(bounds.minY, frame.minY, "\(direction): no overhang")
            case .up, .down:
                XCTAssertGreaterThanOrEqual(bounds.minY, spill.minY, "\(direction)")
                XCTAssertLessThanOrEqual(bounds.maxY, spill.maxY, "\(direction)")
                XCTAssertLessThan(bounds.minX, frame.minX, "\(direction): no overhang")
            }
        }
    }

    /// A look at it: set `TOOLTIP_TAIL_RENDER_PATH` and a card is drawn facing
    /// each way, black on light, so the silhouette is what you see.
    func testRendersEveryDirection() throws {
        let now = Date()
        var snapshot = ProviderSnapshot(
            id: "claude", displayName: "Claude", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [
                LimitWindow(id: "session", label: "Current session", usedFraction: 0.23,
                            resetsAt: now.addingTimeInterval(3 * 3600)),
                LimitWindow(id: "all", label: "All models", usedFraction: 0.80,
                            resetsAt: now.addingTimeInterval(30 * 3600)),
                LimitWindow(id: "weekly_scoped", label: "Fable", usedFraction: 0.42,
                            resetsAt: now.addingTimeInterval(30 * 3600))
            ],
            headlineID: "weekly_scoped",
            secondaryID: "session"
        )
        // A pace on two of them, so the card shows both things it can say.
        snapshot.pace["session"] = UsagePace(perSecond: 0.10 / (30 * 60))
        snapshot.pace["all"] = UsagePace(perSecond: 0.01 / (30 * 60))
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
