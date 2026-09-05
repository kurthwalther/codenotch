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
                HStack(spacing: 90) {
                    Text(edge.title).frame(width: 60, alignment: .leading)
                    SettingsOrb(isHovered: true, edge: edge)
                        .frame(width: 150, height: 110)
                    SettingsOrb(isHovered: true, edge: edge, symbol: "cup.and.saucer.fill",
                                atStart: true, spin: 0, tint: Palette.cappuccino,
                                caption: "Awake while agents work", detail: "Holding now")
                        .frame(width: 150, height: 110)
                    SettingsOrb(isHovered: true, edge: edge, symbol: "cup.and.saucer.fill",
                                atStart: true, spin: 0, tint: Palette.cappuccino, dim: true,
                                caption: "Awake while agents work", detail: "None running, may sleep")
                        .frame(width: 150, height: 110)
                    SettingsOrb(isHovered: true, edge: edge, symbol: "cup.and.saucer",
                                atStart: true, spin: 0, tint: Palette.textSecondary,
                                caption: "Off")
                        .frame(width: 150, height: 110)
                    SettingsOrb(isHovered: true, edge: edge, symbol: "cup.and.heat.waves.fill",
                                atStart: true, spin: 0, tint: Palette.espresso, glow: true,
                                caption: "Awake while sessions open", detail: "Holding now")
                        .frame(width: 150, height: 110)
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
