import SwiftUI

/// What the cell needs of a second window: how much is left, and the colour
/// that amount takes — the same bands the ring uses, so the two gauges never
/// disagree about what "getting low" looks like.
struct SecondaryReading: Equatable {
    let usedFraction: Double

    var remaining: Double { max(0, 1 - usedFraction) }
    var band: UsageBand { UsageBand.band(for: usedFraction) }
}
