import XCTest
@testable import Codenotch

/// Choosing which window the ring draws, end to end short of the screen: the
/// preference that holds it and the names the choices are offered under.
@MainActor
final class RingChoiceTests: XCTestCase {
    private func scratch() -> UserDefaults {
        let name = "ring-choice-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testTheChoiceIsRememberedPerProvider() {
        let defaults = scratch()
        let first = Preferences(defaults: defaults)
        XCTAssertNil(first.ringWindow(for: "claude"))
        first.setRingWindow("weekly_scoped", for: "claude")
        first.setRingWindow("secondary", for: "codex")

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.ringWindow(for: "claude"), "weekly_scoped")
        XCTAssertEqual(second.ringWindow(for: "codex"), "secondary")
        XCTAssertNil(second.ringWindow(for: "cursor"))
    }

    func testClearingAChoiceForgetsIt() {
        let prefs = Preferences(defaults: scratch())
        prefs.setRingWindow("weekly_all", for: "claude")
        prefs.setRingWindow(nil, for: "claude")
        XCTAssertNil(prefs.ringWindow(for: "claude"))
    }

    /// The model-scoped weekly window carries the model's name, not the API's
    /// word for the mechanism.
    func testTheScopedWindowIsNamedAfterItsModel() {
        XCTAssertEqual(UsageResponse.label(forKind: "weekly_scoped"), "Fable")
        XCTAssertEqual(UsageResponse.label(forKind: "session"), "Current session")
        XCTAssertEqual(UsageResponse.label(forKind: "weekly_all"), "All models")
    }

    /// Settings lists the windows a provider showed last, so the picker can
    /// offer real choices rather than guesses.
    func testSummariesCarryTheWindowsAndTheDefault() {
        let summary = ProviderSummary(
            id: "claude", name: "Claude", glyph: .claude, account: nil, signIn: .guidance("Sign in with the claude command"),
            windows: [WindowChoice(id: "session", label: "Current session"),
                      WindowChoice(id: "weekly_scoped", label: "Fable")],
            defaultRing: "session"
        )
        XCTAssertEqual(summary.windows.map(\.label), ["Current session", "Fable"])
        XCTAssertEqual(summary.defaultRing, "session")
    }
}
