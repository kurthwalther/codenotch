import SwiftUI

/// Every number in this app's UI is measured off the Figma frame in
/// `docs/design/frame-124-hover-tooltip.png` (2000 x 2000 px), so the layout is
/// *proportionally* exact rather than eyeballed.
///
/// The frame fixes only ratios, never an absolute size, so one anchor picks the
/// scale: the design spec calls the provider ring 44pt across, and it measures
/// 117px in the frame. Change `scale` and the whole surface — notch, rings,
/// type, tooltip — resizes together, still in the design's proportions.
enum Design {
    /// Points per pixel of the design frame.
    static let scale: CGFloat = 44.0 / 117.0

    /// A distance measured in design-frame pixels, in points.
    static func px(_ pixels: CGFloat) -> CGFloat { pixels * scale }

    /// How much smaller than the frame the *notch* is drawn — rings, labels,
    /// pill, orbs — while the tooltip keeps the frame's size, because that is
    /// where there is text to read. The notch only carries a ring, a glyph and
    /// a number, and at the frame's size it was more furniture than reading.
    ///
    /// One for the build, set from Settings at launch and whenever the slider
    /// moves. The frame's own size is 1, which is what the tests measure
    /// against.
    nonisolated(unsafe) static var notchFactor: CGFloat = 1

    /// A notch distance measured in design-frame pixels, in points.
    static func npx(_ pixels: CGFloat) -> CGFloat { pixels * scale * notchFactor }

    /// The notch's point size whose capitals are `pixels` tall in the frame.
    static func notchFontSize(capPixels pixels: CGFloat) -> CGFloat {
        npx(pixels) / capRatio
    }

    /// Cap-height fraction of an em for SF Pro. Text in the frame can only be
    /// measured by its cap height, so this converts back to a point size.
    private static let capRatio: CGFloat = 0.714

    /// The point size whose capital letters are `pixels` tall in the frame.
    static func fontSize(capPixels pixels: CGFloat) -> CGFloat {
        px(pixels) / capRatio
    }
}
