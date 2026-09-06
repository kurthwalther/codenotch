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

    /// The second window's own number, above its bar: a whisper next to the
    /// ring's figure. Cap height 17px.
    static var barPercent: Font {
        Font.system(size: Design.notchFontSize(capPixels: 17), weight: .semibold)
    }

    /// The bar's name under it, a touch larger than the ring's captions.
    /// Cap height 12.5px.
    static var barName: Font {
        Font.system(size: Design.notchFontSize(capPixels: 12.5), weight: .medium)
    }

    /// The countdown under the number. Cap height 16px, at the weight of the
    /// text around it: the one caption people look for, read at a glance
    /// rather than found.
    static var resetLabel: Font {
        Font.system(size: Design.notchFontSize(capPixels: 16), weight: .regular)
    }

    /// The same line once the window is spent. With nothing left above it to
    /// read, how long until it comes back is the only thing the cell still
    /// has to say, so it takes the weight the number no longer needs.
    static var resetLabelSpent: Font {
        Font.system(size: Design.notchFontSize(capPixels: 20), weight: .semibold)
    }

    /// The captions under the numbers — which window, and when it resets.
    /// Cap height 11px: small on purpose, there to be found rather than read
    /// first.
    static var caption: Font {
        Font.system(size: Design.notchFontSize(capPixels: 11), weight: .medium)
    }

    /// The quieter line under it.
    static var orbDetail: Font {
        Font.system(size: Design.notchFontSize(capPixels: 13), weight: .regular)
    }

    /// "Claude Usage". Cap height 26px.
    static let cardTitle = Font.system(size: Design.fontSize(capPixels: 26), weight: .semibold)

    /// "Current session", "73% Used", "Resets in 51 min". Cap height 18px.
    static let cardBody = Font.system(size: Design.fontSize(capPixels: 18), weight: .regular)
}
