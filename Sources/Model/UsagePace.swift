import Foundation

/// How fast a window is being spent, worked out from the readings taken since
/// it last reset — so the tooltip can say when it runs out at this pace.
///
/// No vendor reports this. It is the one number that turns a percentage into
/// a decision — slow down, or carry on — and it only needs what the notch is
/// already fetching every minute.
struct UsagePace: Equatable {
    /// Fraction of the limit spent per second.
    let perSecond: Double

    struct Sample: Codable, Equatable {
        let at: Date
        let used: Double
    }

    /// How far back to look. Long enough to smooth a fetch or two of noise,
    /// short enough that the answer is about what you are doing *now*.
    static let lookback: TimeInterval = 2 * 60 * 60
    /// Less than this between the first and last reading and any rate is a
    /// guess dressed up as a number.
    static let minimumSpan: TimeInterval = 10 * 60

    /// Nil when there is nothing honest to say: too few readings, a window
    /// that is not being spent, or one that reset inside the span.
    static func estimate(from samples: [Sample], now: Date = Date()) -> UsagePace? {
        let recent = samples
            .filter { $0.at > now.addingTimeInterval(-lookback) && $0.at <= now }
            .sorted { $0.at < $1.at }
        guard let last = recent.last else { return nil }

        // Walk back only while the figure was still climbing. A drop is the
        // window resetting, and readings from before it belong to another
        // life of the same window.
        var first = last
        for sample in recent.dropLast().reversed() {
            guard sample.used <= first.used else { break }
            first = sample
        }

        let span = last.at.timeIntervalSince(first.at)
        let spent = last.used - first.used
        guard span >= minimumSpan, spent > 0 else { return nil }
        return UsagePace(perSecond: spent / span)
    }

    /// Seconds until the window is spent, at this pace.
    func timeToEmpty(remaining: Double) -> TimeInterval {
        max(0, remaining) / perSecond
    }

    /// What the tooltip says beside the figure, or nothing when there is
    /// nothing worth a line.
    ///
    /// "Out in" only when it will actually happen before the reset; otherwise
    /// the reassurance, which is the more common answer and the one people
    /// hover to get.
    func text(remaining: Double, resetsAt: Date?, now: Date = Date()) -> String? {
        guard remaining > 0 else { return nil }
        let empty = timeToEmpty(remaining: remaining)
        if let resetsAt, empty >= resetsAt.timeIntervalSince(now) {
            return "Lasts until reset"
        }
        return "Out in \(ElapsedCopy.span(empty))"
    }
}
