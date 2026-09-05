import SwiftUI

/// Sizes are derived from cap heights measured in the design frame, so they
/// track `Design.scale` along with everything else.
enum Typography {
    /// The percent under each provider ring. Cap height 27px in the frame.
    /// Computed, not stored: it follows the notch's own scale.
    static var percent: Font {
        Font.system(size: Design.notchFontSize(capPixels: 27), weight: .semibold)
    }

    /// The word beside the keep-awake handle. Small and on the notch's scale.
    static var orbCaption: Font {
        Font.system(size: Design.notchFontSize(capPixels: 16), weight: .medium)
    }

    /// "Claude Usage". Cap height 26px.
    static let cardTitle = Font.system(size: Design.fontSize(capPixels: 26), weight: .semibold)

    /// "Current session", "73% Used", "Resets in 51 min". Cap height 18px.
    static let cardBody = Font.system(size: Design.fontSize(capPixels: 18), weight: .regular)
}
