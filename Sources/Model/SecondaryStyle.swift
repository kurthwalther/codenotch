import SwiftUI

/// How a provider's second window is drawn in its cell, when one is chosen.
enum SecondaryStyle: String, CaseIterable, Identifiable {
    /// A thinner ring inside the main one, Activity-rings style.
    case innerRing
    /// The disc inside the ring fills from the bottom, like a level.
    case level
    /// A miniature bar between the ring and the percentage.
    case bar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .innerRing: return "Inner ring"
        case .level:     return "Level"
        case .bar:       return "Bar"
        }
    }

    var explanation: String {
        switch self {
        case .innerRing:
            return "A second, thinner ring inside the first. The glyph makes a "
                 + "little room for it."
        case .level:
            return "The inside of the ring fills from the bottom, in a tint of "
                 + "the window's colour. Quiet, and more a feeling than a number."
        case .bar:
            return "A small bar between the ring and the percentage, the same "
                 + "shape the card uses. Every cell keeps room for it."
        }
    }
}

/// What the cell needs of the second window: how much is left, and the
/// colour that amount takes.
struct SecondaryReading: Equatable {
    let usedFraction: Double

    var remaining: Double { max(0, 1 - usedFraction) }
    var band: UsageBand { UsageBand.band(for: usedFraction) }
}
