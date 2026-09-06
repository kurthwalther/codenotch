import Foundation

/// Notices the moment a limit window rolls over.
///
/// The countdown under a number reaching zero is the one moment in a window's
/// life worth looking up for: the quota is back. The reading itself cannot
/// say so — the app is still holding the snapshot it had a moment ago, and
/// its `resetsAt` will not move until the next poll — so the crossing is
/// watched here, against the clock.
struct ResetWatch {
    /// The reset each window is counting towards, while that is still ahead.
    private var pending: [String: Date] = [:]

    /// Whether any watched window has just rolled over.
    ///
    /// Fires once per crossing: the window stops being watched the moment it
    /// does, and is picked up again when a refresh brings the next reset. A
    /// window first seen with its reset already past is not a crossing —
    /// otherwise every launch after one would claim it had just happened.
    mutating func crossed(now: Date, resets: [String: Date]) -> Bool {
        var fired = false
        for (id, at) in resets {
            if let watched = pending[id], now >= watched { fired = true }
            pending[id] = at > now ? at : nil
        }
        // A provider that stopped reporting stops being watched.
        pending = pending.filter { resets[$0.key] != nil }
        return fired
    }
}
