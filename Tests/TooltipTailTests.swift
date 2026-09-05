import XCTest
import SwiftUI
@testable import Codenotch

/// The tail is written once, pointing right, and turned onto the other three
/// directions. These pin the turn — the tip lands on the side the direction
/// names and the base sits flush against the card opposite — and the profile
/// itself: a bubble's tail, full at the card and sweeping in to a point.
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

    /// Where a straight edge from base corner to tip would run at a given
    /// distance along the tail — the triangle this replaced.
    private func straightEdge(at fraction: CGFloat, in r: CGRect) -> (upper: CGFloat, lower: CGFloat) {
        let inset = r.midY * fraction
        return (r.minY + inset, r.maxY - inset)
    }

    func testTheProfileIsABellyThenAHook() {
        let r = rect(.leading)
        // Just inside the base, near both corners: the belly leaves the card
        // level, so the tail is still full-height there.
        XCTAssertTrue(contains(.leading, CGPoint(x: 0.5, y: 1)))
        XCTAssertTrue(contains(.leading, CGPoint(x: 0.5, y: r.maxY - 1)))

        // Well along, the belly bows *out* past where the straight edge would
        // run: a point just inside that line is inside the curve too.
        let belly = straightEdge(at: 0.4, in: r)
        XCTAssertTrue(contains(.leading, CGPoint(x: r.maxX * 0.4, y: belly.upper - 1)))
        XCTAssertTrue(contains(.leading, CGPoint(x: r.maxX * 0.4, y: belly.lower + 1)))

        // Toward the point, the hook sweeps *in* past it: a point just inside
        // the straight line is outside the curve. Measured where the sweep is
        // deepest — it is a subtle curve, about a point deep at this size,
        // which is what keeps the tail a bubble's rather than a thorn.
        let hook = straightEdge(at: 0.75, in: r)
        XCTAssertFalse(contains(.leading, CGPoint(x: r.maxX * 0.75, y: hook.upper + 0.5)))
        XCTAssertFalse(contains(.leading, CGPoint(x: r.maxX * 0.75, y: hook.lower - 0.5)))
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
            headlineID: "weekly_scoped"
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
