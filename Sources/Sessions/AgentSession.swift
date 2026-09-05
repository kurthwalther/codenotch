import Foundation

/// One agent session, whichever tool it belongs to.
///
/// Deliberately a *display* model rather than a mirror of any one tool's file
/// format: Claude Code publishes a session registry, Cursor keeps composer rows
/// in SQLite, and neither shape belongs in the notch. Each monitor does its own
/// parsing and hands back this.
struct AgentSession: Identifiable, Equatable {
    /// What the session is doing right now.
    enum State: Equatable {
        case busy
        case waiting
        case idle
    }

    let id: String
    /// What to call it in the tooltip.
    let name: String
    /// The quieter second line — where it is running, or what it is doing.
    let detail: String
    let state: State
    /// Set while `waiting`: what it wants from you.
    let waitingFor: String?
    /// When it entered its current state.
    let since: Date
    /// Enough to find it on screen again, for the monitors that know.
    var locator: SessionLocator? = nil
}

/// Where a session lives, as far as its monitor can tell: the process, the
/// folder it works in, what launched it, or failing all of those the app to
/// bring forward. `SessionFocus` turns this into a place to go.
struct SessionLocator: Equatable {
    var pid: Int32? = nil
    var cwd: String? = nil
    /// Claude Code's own word for where it was launched from: "cli",
    /// "claude-vscode", "claude-desktop"…
    var entrypoint: String? = nil
    var appBundleID: String? = nil
}
