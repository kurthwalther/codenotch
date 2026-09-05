import SwiftUI

/// The colour a ring or bar takes at a given level of use.
///
/// The thresholds come from the mockup, which shows 21% green, 52% yellow and
/// 73% orange. (The prose table in the design spec says 50–79 is yellow, which
/// would make 73% yellow and contradict the frame it claims to describe — the
/// frame wins.)
enum UsageBand: Equatable {
    case ample       // under half
    case watch       // getting close
    case critical    // nearly out
    case exhausted   // limit hit, waiting for the reset

    /// Where the colours change, in terms of what is *left* — the figure the
    /// rings and bars draw. The frame's own thresholds by default; Settings
    /// can move them for someone who wants the red earlier.
    static func band(for usedFraction: Double,
                     thresholds: UsageThresholds = .standard) -> UsageBand {
        // Compared in "used" terms with a hair of slack, so 0.7 against a red
        // threshold of 30% left lands on red rather than a floating-point
        // whisker short of it.
        let slack = 1e-9
        if usedFraction >= 1 { return .exhausted }
        if usedFraction + slack >= 1 - thresholds.criticalBelowLeft { return .critical }
        if usedFraction + slack >= 1 - thresholds.watchBelowLeft { return .watch }
        return .ample
    }

    var color: Color {
        switch self {
        case .ample:                 return Palette.ample
        case .watch:                 return Palette.watch
        case .critical, .exhausted:  return Palette.critical
        }
    }
}
