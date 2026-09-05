import Foundation

/// "how long has it been like this" — the second half of answering "is Claude
/// still working".
enum ElapsedCopy {
    /// The same span, phrased as a point in the past.
    static func ago(since: Date, now: Date = Date()) -> String {
        let elapsed = text(since: since, now: now)
        return elapsed == "just now" ? elapsed : "\(elapsed) ago"
    }

    /// A span on its own — "1 hr 20 min", "3 days" — never "just now". For
    /// saying how long something will *take* rather than how long ago it was.
    static func span(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((max(0, seconds) / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let restMinutes = minutes % 60
        if hours < 24 {
            return restMinutes == 0 ? "\(hours) hr" : "\(hours) hr \(restMinutes) min"
        }
        // Past a day the minutes are noise, and past two the hours are too.
        let days = hours / 24
        let restHours = hours % 24
        let dayWord = days == 1 ? "day" : "days"
        if days >= 2 || restHours == 0 { return "\(days) \(dayWord)" }
        return "\(days) \(dayWord) \(restHours) hr"
    }

    /// The same span, squeezed for the cell under a ring: "2h 10m", "45m",
    /// "3d 4h". Never more than two parts, and never the word "just now".
    static func compact(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((max(0, seconds) / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let restMinutes = minutes % 60
        if hours < 24 {
            return restMinutes == 0 ? "\(hours)h" : "\(hours)h \(restMinutes)m"
        }
        let days = hours / 24
        let restHours = hours % 24
        return restHours == 0 ? "\(days)d" : "\(days)d \(restHours)h"
    }

    static func text(since: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(since))
        if seconds < 45 { return "just now" }

        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(1, minutes)) min" }

        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return "\(hours) hr" }
        return "\(hours) hr \(rest) min"
    }
}
