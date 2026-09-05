import AppKit

/// Whether what is in front has taken the whole screen.
///
/// The panel joins full-screen spaces on purpose — a reading you can glance at
/// while working is the point — but a film or a slide deck is not working,
/// and a black notch on its edge is in the way. There is no notification for
/// this; the window list is asked instead, which needs no permission for the
/// two things it is asked for: who owns a window, and how big it is.
enum FullscreenDetector {
    static func isFullscreenAppFrontmost(on screen: NSScreen) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]]
        else { return false }
        return Self.covers(screen.frame.size, windows: windows, ownedBy: front.processIdentifier)
    }

    /// True when `owner` has an ordinary window at least the size of the
    /// screen. A window merely zoomed still stops short of the menu bar; only
    /// a full-screen one measures the whole display.
    static func covers(_ screen: CGSize, windows: [[String: Any]], ownedBy owner: pid_t) -> Bool {
        windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == owner,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { return false }
            return width >= screen.width - 1 && height >= screen.height - 1
        }
    }
}
