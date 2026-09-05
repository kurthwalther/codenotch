import XCTest
@testable import Codenotch

/// The small behaviours: hiding for a full-screen app, remembering the pin,
/// refreshing on arrival.
@MainActor
final class PolishTests: XCTestCase {
    private func scratch() -> UserDefaults {
        let name = "polish-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testHidingInFullscreenIsOnByDefaultAndRemembered() {
        let defaults = scratch()
        let first = Preferences(defaults: defaults)
        XCTAssertTrue(first.hideInFullscreen)
        first.hideInFullscreen = false
        XCTAssertFalse(Preferences(defaults: defaults).hideInFullscreen)
    }

    /// A choice made under the two earlier keys — a switch and a scope — is
    /// carried into the one setting that replaced them.
    func testTheOldKeepAwakeKeysAreCarriedAcross() {
        let off = scratch()
        off.set(false, forKey: "keepAwakeWhileWorking")
        XCTAssertEqual(Preferences(defaults: off).keepAwakeMode, .off)

        let working = scratch()
        working.set(true, forKey: "keepAwakeWhileWorking")
        working.set("whileWorking", forKey: "keepAwakeScope")
        XCTAssertEqual(Preferences(defaults: working).keepAwakeMode, .whileWorking)

        XCTAssertEqual(Preferences(defaults: scratch()).keepAwakeMode, .whileOpen, "fresh: while open")

        let chosen = scratch()
        let prefs = Preferences(defaults: chosen)
        prefs.keepAwakeMode = .whileWorking
        XCTAssertEqual(Preferences(defaults: chosen).keepAwakeMode, .whileWorking)
    }

    func testThePinIsRemembered() {
        let defaults = scratch()
        let first = Preferences(defaults: defaults)
        XCTAssertFalse(first.notchPinned)
        first.notchPinned = true
        XCTAssertTrue(Preferences(defaults: defaults).notchPinned)
    }

    /// A window the size of the screen, owned by the app in front, is what
    /// full screen looks like from the window list; a zoomed window stops
    /// short of the menu bar and does not count.
    func testAScreenSizedWindowCountsAsFullScreen() {
        let screen = CGSize(width: 1728, height: 1117)
        func window(_ owner: pid_t, _ w: CGFloat, _ h: CGFloat, layer: Int = 0) -> [String: Any] {
            [kCGWindowOwnerPID as String: owner, kCGWindowLayer as String: layer,
             kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": w, "Height": h] as [String: CGFloat]]
        }
        XCTAssertTrue(FullscreenDetector.covers(screen, windows: [window(7, 1728, 1117)], ownedBy: 7))
        XCTAssertFalse(FullscreenDetector.covers(screen, windows: [window(7, 1728, 1080)], ownedBy: 7),
                       "zoomed, not full screen")
        XCTAssertFalse(FullscreenDetector.covers(screen, windows: [window(8, 1728, 1117)], ownedBy: 7),
                       "someone else's window")
        XCTAssertFalse(FullscreenDetector.covers(screen, windows: [window(7, 1728, 1117, layer: 25)], ownedBy: 7),
                       "not an ordinary window")
    }
}
