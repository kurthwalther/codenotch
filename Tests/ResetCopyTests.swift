import XCTest
@testable import Codenotch

final class ResetCopyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testRelativeUnderAnHour() {
        XCTAssertEqual(
            ResetCopy.text(for: now.addingTimeInterval(51 * 60), now: now),
            "Resets in 51 min"
        )
    }

    func testRoundsToTheNearestMinute() {
        XCTAssertEqual(
            ResetCopy.text(for: now.addingTimeInterval(50 * 60 + 20), now: now),
            "Resets in 50 min"
        )
        XCTAssertEqual(
            ResetCopy.text(for: now.addingTimeInterval(50 * 60 + 40), now: now),
            "Resets in 51 min"
        )
    }

    /// The edge the whole rule turns on: at 60 minutes it stops counting down
    /// and names a time instead, so "Resets in 60 min" never appears.
    func testSwitchesToAbsoluteAtSixtyMinutes() {
        let atTheEdge = ResetCopy.text(for: now.addingTimeInterval(60 * 60), now: now)
        XCTAssertFalse(atTheEdge.contains("min"))
        XCTAssertTrue(atTheEdge.hasPrefix("Resets "))

        let justUnder = ResetCopy.text(for: now.addingTimeInterval(59 * 60 + 20), now: now)
        XCTAssertEqual(justUnder, "Resets in 59 min")

        // 59m40s rounds to 60, which must not print as "60 min" either.
        let rounding = ResetCopy.text(for: now.addingTimeInterval(59 * 60 + 40), now: now)
        XCTAssertFalse(rounding.contains("min"))
    }

    /// The frame writes "Resets Thu 12:00 AM"; a localised template gives
    /// "12.00 AM" in some regions, so the colon is pinned.
    ///
    /// Only between the digits. The day period is the locale's own — Spanish
    /// ones write "p.m." — and checking the whole string for a full stop
    /// failed on every Mac set to one of them.
    func testAbsoluteTimeUsesAColon() {
        let text = ResetCopy.text(for: now.addingTimeInterval(6 * 60 * 60), now: now)
        XCTAssertNotNil(text.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression),
                        "expected h:mm in \(text)")
        XCTAssertNil(text.range(of: #"\d\.\d"#, options: .regularExpression),
                     "expected no full stop between the digits in \(text)")
    }

    func testPastResetsReadAsResetting() {
        XCTAssertEqual(ResetCopy.text(for: now.addingTimeInterval(-5), now: now), "Resetting…")
    }
}

/// A weekday only identifies a day inside the coming week. Codex's monthly
/// window resets nearly four weeks out, and "Resets Mon 3:55 PM" read as *this*
/// Monday — which is what made the app appear to disagree with Codex's own
/// "Resets Sep 28".
final class ResetCopyDistantDateTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    /// The reported case: 1 Sep to 28 Sep.
    func testAMonthAwayShowsTheDateNotAWeekday() {
        let text = ResetCopy.text(for: date("2026-09-28T15:55:00+07:00"),
                                  now: date("2026-09-01T23:30:00+07:00"),
                                  calendar: calendar)
        XCTAssertTrue(text.contains("28"), "the day of the month is missing: \(text)")
        XCTAssertFalse(text.contains("Mon"), "a date four weeks out still reads as a weekday")
        XCTAssertFalse(text.contains("PM"), "a time four weeks out is noise")
    }

    /// Inside the week a weekday is the friendlier answer, and unambiguous.
    func testWithinTheWeekKeepsTheWeekdayAndTime() {
        let text = ResetCopy.text(for: date("2026-09-04T12:00:00+07:00"),
                                  now: date("2026-09-01T23:30:00+07:00"),
                                  calendar: calendar)
        XCTAssertTrue(text.contains("12:00"), "expected a time: \(text)")
    }

    /// Seven days out is the same weekday name as today — the first genuinely
    /// ambiguous distance, so it is where the date form starts.
    func testSevenDaysIsAlreadyTooFarForAWeekday() {
        let text = ResetCopy.text(for: date("2026-09-08T12:00:00+07:00"),
                                  now: date("2026-09-01T12:00:00+07:00"),
                                  calendar: calendar)
        XCTAssertTrue(text.contains("8"), "expected a date: \(text)")
    }

    func testCountsWholeCalendarDaysNotElapsedHours() {
        // 23:30 to 00:30 the next day is one hour, but a different day.
        XCTAssertEqual(
            ResetCopy.daysApart(from: date("2026-09-01T23:30:00+07:00"),
                                to: date("2026-09-02T00:30:00+07:00"),
                                calendar: calendar), 1)
    }
}

/// Vendors disagree on which end of the figure to show — Codex writes "87%
/// remaining", Claude writes a percentage used. A notch that picks one side
/// makes the user convert in their head, so both ends are shown, what is left
/// first: that is what the bar above the line is drawn as.
final class WindowSummaryTests: XCTestCase {
    private func window(_ fraction: Double) -> LimitWindow {
        LimitWindow(id: "w", label: "Monthly limit", usedFraction: fraction)
    }

    func testItShowsBothEndsOfTheSameFigure() {
        XCTAssertEqual(window(0.12).summary, "88% left · 12% used")
    }

    /// The two halves must always agree, or the line contradicts itself.
    func testTheHalvesAlwaysSumToAHundred() {
        for percent in stride(from: 0, through: 100, by: 7) {
            let text = window(Double(percent) / 100).summary
            let numbers = text.split(separator: " ").compactMap { Int($0.replacingOccurrences(of: "%", with: "")) }
            XCTAssertEqual(numbers.count, 2, "unexpected wording: \(text)")
            XCTAssertEqual(numbers[0] + numbers[1], 100, "\(text) does not add up")
        }
    }

    /// A limit can be reported past full; "-4% left" would be nonsense.
    func testAnOverspentLimitNeverGoesNegative() {
        XCTAssertEqual(window(1.04).summary, "0% left · 104% used")
    }

    /// Counts have no denominator, so they keep their own wording.
    func testCountsAreUntouched() {
        XCTAssertEqual(LimitWindow(id: "w", label: "Requests", used: 8).summary, "8 used")
        XCTAssertEqual(LimitWindow(id: "w", label: "Requests", remaining: 3).summary, "3 left")
    }
}
