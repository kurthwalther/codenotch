import XCTest
import SwiftUI
@testable import Codenotch

/// The two handles, hovered, on every edge — so the caption's placement can
/// be looked at rather than reasoned about. Set `ORB_RENDER_PATH`.
@MainActor
final class OrbRenderTests: XCTestCase {
    func testTheHandlesLayOutOnEveryEdge() throws {
        let view = VStack(spacing: 30) {
            ForEach(NotchEdge.allCases) { edge in
                HStack(spacing: 60) {
                    Text(edge.title).frame(width: 60, alignment: .leading)
                    SettingsOrb(isHovered: true, edge: edge)
                        .frame(width: 140, height: 90)
                    SettingsOrb(isHovered: true, edge: edge, symbol: "cup.and.saucer.fill",
                                atStart: true, spin: 0, tint: Palette.cappuccino,
                                caption: "Keeping awake")
                        .frame(width: 140, height: 90)
                    SettingsOrb(isHovered: true, edge: edge, symbol: "cup.and.saucer.fill",
                                atStart: true, spin: 0, tint: Palette.cappuccino, dim: true,
                                caption: "No agents running")
                        .frame(width: 140, height: 90)
                    SettingsOrb(isHovered: true, edge: edge, symbol: "cup.and.saucer",
                                atStart: true, spin: 0, tint: Palette.textSecondary,
                                caption: "Off")
                        .frame(width: 140, height: 90)
                }
            }
        }
        .padding(60)
        .background(Color(white: 0.85))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, 400)
        if let path = ProcessInfo.processInfo.environment["ORB_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
