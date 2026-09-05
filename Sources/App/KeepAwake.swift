import Combine
import Foundation
import IOKit.pwr_mgt

/// Holds the Mac awake while an agent is working — what Caffeine does, but
/// only for as long as something is actually busy.
///
/// A power assertion rather than `caffeinate`: it is released the instant the
/// last session goes idle, and it dies with the process, so a crash can never
/// leave the machine stuck awake. What an assertion cannot do is override the
/// lid — macOS sleeps a closed MacBook regardless, unless it is on power with
/// an external display, and nothing short of `pmset disablesleep` as root
/// changes that.
@MainActor
final class KeepAwake: ObservableObject {
    /// What to hold open.
    enum Scope: Equatable {
        /// The Mac stays up; the display may still go dark.
        case system
        /// The display stays lit too.
        case display
    }

    /// The reason macOS shows beside the assertion, in Activity Monitor's
    /// "Preventing Sleep" column and in `pmset -g assertions`.
    static let reason = "Codenotch: an agent is working"

    /// Published so the notch can show, on its handle, that the Mac is being
    /// held right now rather than merely that it would be.
    @Published private(set) var held: Scope?
    private var assertion = IOPMAssertionID(kIOPMNullAssertionID)

    /// What should be held, given the settings and what every session is
    /// doing. Pure, so it can be pinned by tests without taking a real
    /// assertion.
    ///
    /// Only `busy` counts. A session waiting on you is not going anywhere
    /// until you come back, and neither is anything lost by the Mac dozing
    /// off in the meantime.
    static func wanted(enabled: Bool, display: Bool,
                       sessions: [String: [AgentSession]]) -> Scope? {
        guard enabled,
              sessions.values.contains(where: { $0.contains { $0.state == .busy } })
        else { return nil }
        return display ? .display : .system
    }

    /// Takes, swaps or drops the assertion so that exactly `scope` is held.
    func hold(_ scope: Scope?) {
        guard scope != held else { return }
        release()
        guard let scope else { return }

        // Preventing display sleep implies preventing system sleep, so one
        // assertion covers either scope.
        let type = scope == .display
            ? kIOPMAssertPreventUserIdleDisplaySleep
            : kIOPMAssertPreventUserIdleSystemSleep
        var id = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            Log.sessions.error("keep awake: assertion refused (\(result, privacy: .public))")
            return
        }
        assertion = id
        held = scope
        let what = scope == .display ? "system and display" : "system"
        Log.sessions.info("keep awake: holding \(what, privacy: .public)")
    }

    private func release() {
        guard held != nil else { return }
        IOPMAssertionRelease(assertion)
        assertion = IOPMAssertionID(kIOPMNullAssertionID)
        held = nil
        Log.sessions.info("keep awake: released")
    }
}
