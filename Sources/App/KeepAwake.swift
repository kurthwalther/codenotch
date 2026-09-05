import Combine
import Foundation
import IOKit.pwr_mgt

/// Whether, and when, the Mac is held awake. One setting with three
/// positions, and the handle above the notch steps through them.
enum KeepAwakeMode: String, CaseIterable, Identifiable {
    /// Never. The Mac sleeps as it would without Codenotch.
    case off
    /// Only while a session is busy. Released the moment every agent is idle
    /// or waiting on you.
    case whileWorking
    /// As long as any session exists at all, idle or waiting included — for
    /// driving Claude Code from a phone while the Mac sits closed on a desk,
    /// where "waiting on you" is precisely the moment it must not doze off.
    case whileOpen

    var id: String { rawValue }

    var isOn: Bool { self != .off }

    /// The next position round: off, working, open, off…
    var next: KeepAwakeMode {
        switch self {
        case .off:          return .whileWorking
        case .whileWorking: return .whileOpen
        case .whileOpen:    return .off
        }
    }

    var title: String {
        switch self {
        case .off:          return "Off"
        case .whileWorking: return "While working"
        case .whileOpen:    return "While open"
        }
    }

    var explanation: String {
        switch self {
        case .off:
            return "The Mac sleeps as it always has."
        case .whileWorking:
            return "Held while any agent is busy, and released as soon as every "
                 + "one is idle or waiting on you."
        case .whileOpen:
            return "Held for as long as any session exists, even one waiting on "
                 + "you — so Claude Code can be driven remotely without the Mac "
                 + "dozing off. The display still sleeps; only the Mac stays up. "
                 + "A session left open on battery keeps it awake too."
        }
    }
}

/// Holds the Mac awake while an agent is working — what Caffeine does, but
/// only for as long as something is actually busy — or, if asked, for as
/// long as any session is open at all.
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
    /// While working, only `busy` counts: a session waiting on you is not
    /// going anywhere until you come back. While open, any session counts,
    /// because "waiting on you" may mean waiting on your phone.
    static func wanted(mode: KeepAwakeMode, display: Bool,
                       sessions: [String: [AgentSession]]) -> Scope? {
        guard holds(mode, sessions: sessions) else { return nil }
        return display ? .display : .system
    }

    static func holds(_ mode: KeepAwakeMode, sessions: [String: [AgentSession]]) -> Bool {
        switch mode {
        case .off:
            return false
        case .whileWorking:
            return sessions.values.contains { $0.contains { $0.state == .busy } }
        case .whileOpen:
            return sessions.values.contains { !$0.isEmpty }
        }
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
