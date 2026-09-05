import Combine
import Foundation
import ServiceManagement
import os

/// What the user has chosen, kept in `UserDefaults`.
@MainActor
final class Preferences: ObservableObject {
    /// Providers the user has switched off. Stored as the *disconnected* set
    /// rather than the connected one, so a provider added in a later version is
    /// on by default instead of silently staying dark.
    ///
    /// Switching one off is not merely hiding it: the store stops fetching it,
    /// so its credential is never read at all.
    @Published var disconnectedProviders: Set<String> {
        didSet { defaults.set(Array(disconnectedProviders), forKey: Keys.disconnected) }
    }

    /// How much of itself the notch shows at rest.
    @Published var notchVisibility: NotchVisibility {
        didSet { defaults.set(notchVisibility.rawValue, forKey: Keys.visibility) }
    }

    /// Which screen edge the notch is welded to.
    @Published var notchEdge: NotchEdge {
        didSet { defaults.set(notchEdge.rawValue, forKey: Keys.edge) }
    }

    /// Where the app itself shows up: Dock, menu bar, or nowhere.
    @Published var appPresence: AppPresence {
        didSet { defaults.set(appPresence.rawValue, forKey: Keys.presence) }
    }

    /// The version whose changes have already been shown.
    ///
    /// Written when the What's New dialogue is dismissed rather than when it
    /// opens, so a crash in between cannot swallow the one launch it was going
    /// to appear on.
    @Published var lastSeenVersion: String? {
        didSet { defaults.set(lastSeenVersion, forKey: Keys.lastSeenVersion) }
    }

    /// Hold the Mac awake while any agent session is busy — see `KeepAwake`.
    @Published var keepAwakeWhileWorking: Bool {
        didSet { defaults.set(keepAwakeWhileWorking, forKey: Keys.keepAwake) }
    }

    /// While holding it awake, keep the display lit as well.
    @Published var keepDisplayAwake: Bool {
        didSet { defaults.set(keepDisplayAwake, forKey: Keys.keepDisplay) }
    }

    /// Which metered window each provider's ring draws, chosen by the user.
    /// Keyed by provider id; absent means the provider's own default.
    @Published var ringWindows: [String: String] {
        didSet { defaults.set(ringWindows, forKey: Keys.ringWindows) }
    }

    /// A second window per provider, shown beside the ring's. Absent means none.
    @Published var secondaryWindows: [String: String] {
        didSet { defaults.set(secondaryWindows, forKey: Keys.secondaryWindows) }
    }

    /// How big the notch is, as a share of the design frame's size. The
    /// tooltip is not affected.
    @Published var notchScale: Double {
        didSet { defaults.set(notchScale, forKey: Keys.notchScale) }
    }

    static let notchScaleRange: ClosedRange<Double> = 0.6...1.0
    static let defaultNotchScale = 0.8

    /// Get out of the way while an app has the whole screen.
    @Published var hideInFullscreen: Bool {
        didSet { defaults.set(hideInFullscreen, forKey: Keys.hideInFullscreen) }
    }

    /// Whether the notch was held open by a click when the app last quit, so
    /// it can come back that way. Only meaningful under "Show on hover".
    @Published var notchPinned: Bool {
        didSet { defaults.set(notchPinned, forKey: Keys.notchPinned) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != Self.isRegisteredForLogin else { return }
            applyLaunchAtLogin()
        }
    }

    /// Set when the login-item request was refused, so the UI can say so rather
    /// than quietly flipping the switch back.
    @Published private(set) var launchAtLoginProblem: String?

    private let defaults: UserDefaults
    private enum Keys {
        /// The old name. Kept so existing choices survive the rename.
        static let disconnected = "hiddenProviders"
        static let hasLaunched = "hasLaunchedBefore"
        static let visibility = "notchVisibility"
        static let presence = "appPresence"
        static let edge = "notchEdge"
        static let lastSeenVersion = "lastSeenVersion"
        static let keepAwake = "keepAwakeWhileWorking"
        static let keepDisplay = "keepDisplayAwake"
        static let ringWindows = "ringWindows"
        static let secondaryWindows = "secondaryWindows"
        static let notchScale = "notchScale"
        static let hideInFullscreen = "hideInFullscreen"
        static let notchPinned = "notchPinned"
    }

    /// True the very first time this copy runs, and never again.
    ///
    /// Deliberately *not* inferred from "there are no readings yet" — that is
    /// also true of someone who switched every provider off, and re-introducing
    /// them to the app every launch would be worse than never introducing them
    /// at all.
    let isFirstLaunch: Bool

    /// The bundle identifier before the app was renamed to Codenotch.
    ///
    /// A bundle id is the name of the defaults domain, so renaming the app
    /// silently moved every setting to a new, empty one — connection choices,
    /// the notch's mode, the archived readings, all apparently lost. Copying
    /// the old domain across once is the difference between a rename and what
    /// looks like a reset.
    private static let previousDomain = "com.vinz.usagenotch"

    static func migrateFromPreviousName(into defaults: UserDefaults = .standard,
                                        from domain: String = previousDomain) {
        // The emptiness test has to be about the object being written to, not
        // about `Bundle.main` — under test those are different domains, and the
        // first version happily copied real settings into a test's scratch
        // suite. `hasLaunched` is the sentinel: `Preferences.init` sets it, so
        // its absence means nothing has ever used this domain.
        guard defaults.object(forKey: Keys.hasLaunched) == nil,
              let old = defaults.persistentDomain(forName: domain), !old.isEmpty
        else { return }

        for (key, value) in old { defaults.set(value, forKey: key) }
        Log.usage.info("migrated \(old.count) settings from the previous app name")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isFirstLaunch = !defaults.bool(forKey: Keys.hasLaunched)
        defaults.set(true, forKey: Keys.hasLaunched)
        self.disconnectedProviders = Set(defaults.stringArray(forKey: Keys.disconnected) ?? [])
        // Absent means never chosen, which is the hover behaviour the app was
        // designed around — not hidden, which would make a fresh install look
        // like it failed to start.
        self.notchVisibility = defaults.string(forKey: Keys.visibility)
            .flatMap(NotchVisibility.init(rawValue:)) ?? .onHover
        // Absent means never chosen. The Dock is the default because it is the
        // findable one — a new user who cannot see the app anywhere has no way
        // to learn it is running.
        self.appPresence = defaults.string(forKey: Keys.presence)
            .flatMap(AppPresence.init(rawValue:)) ?? .dock
        // The right edge is where the notch has always been, and it is the one
        // side of a Mac that no system chrome claims by default.
        self.notchEdge = defaults.string(forKey: Keys.edge)
            .flatMap(NotchEdge.init(rawValue:)) ?? .right
        // Absent means nothing has been shown yet, which is true of a fresh
        // install — so the current release reads as new to it.
        self.lastSeenVersion = defaults.string(forKey: Keys.lastSeenVersion)
        // On by default: the point of leaving an agent to run is that it
        // finishes, and a Mac that dozed off halfway is the one way it cannot.
        // Absent means never chosen.
        self.keepAwakeWhileWorking = defaults.object(forKey: Keys.keepAwake) as? Bool ?? true
        // The display is a separate question — the agent does not need it lit.
        self.keepDisplayAwake = defaults.bool(forKey: Keys.keepDisplay)
        self.ringWindows = defaults.dictionary(forKey: Keys.ringWindows) as? [String: String] ?? [:]
        self.secondaryWindows = defaults.dictionary(forKey: Keys.secondaryWindows) as? [String: String] ?? [:]
        // Smaller than the frame by default: the notch carries a ring, a
        // glyph and a number, and at the frame's size it was more furniture
        // than reading. Absent means never chosen.
        let scale = defaults.object(forKey: Keys.notchScale) as? Double ?? Self.defaultNotchScale
        self.notchScale = min(max(scale, Self.notchScaleRange.lowerBound), Self.notchScaleRange.upperBound)
        // On by default: a film or a slide deck is the one time nobody wants
        // a reading on the screen's edge. Absent means never chosen.
        self.hideInFullscreen = defaults.object(forKey: Keys.hideInFullscreen) as? Bool ?? true
        self.notchPinned = defaults.bool(forKey: Keys.notchPinned)
        // Read from the system rather than from our own store: the user can turn
        // this off in System Settings, and a remembered `true` would then be a lie.
        self.launchAtLogin = Self.isRegisteredForLogin
    }

    func ringWindow(for providerID: String) -> String? { ringWindows[providerID] }

    func setRingWindow(_ windowID: String?, for providerID: String) {
        ringWindows[providerID] = windowID
    }

    func secondaryWindow(for providerID: String) -> String? { secondaryWindows[providerID] }

    func setSecondaryWindow(_ windowID: String?, for providerID: String) {
        secondaryWindows[providerID] = windowID
    }

    func isConnected(_ providerID: String) -> Bool {
        !disconnectedProviders.contains(providerID)
    }

    func setConnected(_ connected: Bool, for providerID: String) {
        if connected {
            disconnectedProviders.remove(providerID)
        } else {
            disconnectedProviders.insert(providerID)
        }
    }

    /// Forget everything this app has stored and quit.
    ///
    /// Deleting an app on macOS leaves `~/Library` untouched, so reinstalling
    /// brings back the old readings, the old connection choices and the old
    /// first-launch flag — which is exactly what makes a reinstall look broken.
    /// Nothing but the app itself can clean that up, so the app has to offer it.
    ///
    /// Not tied to uninstalling: a reinstall is indistinguishable from an
    /// update, and wiping data on every Sparkle update would be catastrophic.
    /// It has to be something the user asks for.
    static func eraseAllData() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.vinz.codenotch"
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()

        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        for relative in ["Caches/\(bundleID)",
                         "WebKit/\(bundleID)",
                         "HTTPStorages/\(bundleID)",
                         "HTTPStorages/\(bundleID).binarycookies",
                         "Saved Application State/\(bundleID).savedState"] {
            if let url = library?.appendingPathComponent(relative) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Login item

    static var isRegisteredForLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginProblem = nil
        } catch {
            // Commonly refused for an app running from a build directory rather
            // than /Applications, which is worth saying plainly.
            Log.usage.error("launch at login failed: \(error.localizedDescription, privacy: .public)")
            launchAtLoginProblem = "macOS refused this — try moving Codenotch to /Applications."
            launchAtLogin = Self.isRegisteredForLogin
        }
    }
}
