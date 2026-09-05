import SwiftUI

/// Where green turns to yellow and yellow to red, as shares of the limit
/// still left. The frame draws 50% and 30%; someone rationing a weekly limit
/// may want the warning sooner.
struct UsageThresholds: Equatable {
    /// Below this much left, the ring goes yellow.
    var watchBelowLeft: Double = 0.5
    /// Below this much left, red.
    var criticalBelowLeft: Double = 0.3

    static let standard = UsageThresholds()

    /// Red can never sit above yellow; the pair is kept in order however the
    /// sliders are dragged.
    var ordered: UsageThresholds {
        UsageThresholds(watchBelowLeft: max(watchBelowLeft, criticalBelowLeft),
                        criticalBelowLeft: min(watchBelowLeft, criticalBelowLeft))
    }
}

private struct UsageThresholdsKey: EnvironmentKey {
    static let defaultValue = UsageThresholds.standard
}

extension EnvironmentValues {
    /// Set once at the root, read wherever a colour is chosen — so a change
    /// in Settings recolours every ring and bar without anything being handed
    /// down by hand.
    var usageThresholds: UsageThresholds {
        get { self[UsageThresholdsKey.self] }
        set { self[UsageThresholdsKey.self] = newValue }
    }
}
