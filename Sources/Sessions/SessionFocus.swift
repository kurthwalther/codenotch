import AppKit
import Darwin
import Foundation

/// Where a click on a session's row goes.
enum SessionDestination: Equatable {
    /// super.engineering: its own command selects the worktree for the folder
    /// and brings the app forward, which lands on the session's tab.
    case superconductor(cwd: String)
    /// Terminal.app or iTerm2: the tab on this tty, by Apple event.
    case terminalTab(bundleID: String, tty: String)
    /// An editor: opening the folder again lands on the window that has it.
    case folder(bundleID: String, cwd: String)
    /// Just the app, forward.
    case app(bundleID: String)
}

/// What the resolver asks about processes — behind a protocol so the choice
/// of destination can be pinned without live processes to walk.
protocol ProcessInspecting {
    func parent(of pid: Int32) -> Int32?
    /// "/dev/ttys002", or nil for a process with no controlling terminal.
    func tty(of pid: Int32) -> String?
    /// The bundle identifier of the app this pid *is*, if it is one.
    func bundleID(of pid: Int32) -> String?
    func isRunning(bundleID: String) -> Bool
}

/// Turns a session's locator into a place to go, and goes there.
///
/// Precision depends on what the monitor knew. A Claude Code session comes
/// with its pid, so the app hosting it can be found by walking up the process
/// tree — the terminal it runs in, or the editor whose extension launched it
/// — and that app decides how exact the landing can be. Cursor and
/// Antigravity sessions know only their app. A Codex rollout knows only its
/// folder.
enum SessionFocus {
    static let superconductorID = "com.zarifpour.superconductor"
    static let terminalIDs: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2"]
    /// Editors that reuse the window already holding a folder when asked to
    /// open it again.
    static let editorIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.exafunction.windsurf", "com.google.antigravity"
    ]
    /// How far up the tree to look for an app before giving up. A shell or
    /// two, a launcher, the app: never more than a handful.
    static let ancestry = 12

    static func destination(for locator: SessionLocator,
                            processes: ProcessInspecting) -> SessionDestination? {
        if let pid = locator.pid, let host = hostingApp(of: pid, processes: processes) {
            if host == superconductorID, let cwd = locator.cwd {
                return .superconductor(cwd: cwd)
            }
            if terminalIDs.contains(host), let tty = processes.tty(of: pid) {
                return .terminalTab(bundleID: host, tty: tty)
            }
            if editorIDs.contains(host), let cwd = locator.cwd {
                return .folder(bundleID: host, cwd: cwd)
            }
            return .app(bundleID: host)
        }
        if let cwd = locator.cwd, processes.isRunning(bundleID: superconductorID) {
            return .superconductor(cwd: cwd)
        }
        if let app = locator.appBundleID {
            return .app(bundleID: app)
        }
        return nil
    }

    /// The nearest ancestor that is an application, the session's pid included.
    static func hostingApp(of pid: Int32, processes: ProcessInspecting) -> String? {
        var current = pid
        for _ in 0..<ancestry {
            if let app = processes.bundleID(of: current) { return app }
            guard let parent = processes.parent(of: current), parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    /// Resolve and go, for a session the user clicked.
    @MainActor
    static func focus(_ session: AgentSession) {
        guard let locator = session.locator,
              let destination = destination(for: locator, processes: LiveProcesses())
        else { return }
        Log.sessions.notice("focus \(session.id, privacy: .public): \(String(describing: destination), privacy: .public)")
        go(to: destination)
    }

    @MainActor
    static func go(to destination: SessionDestination) {
        switch destination {
        case .app(let id):
            activate(id)
        case .folder(let id, let cwd):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: app,
                                    configuration: configuration)
        case .terminalTab(let id, let tty):
            activate(id)
            runAppleScript(Self.selectTabScript(bundleID: id, tty: tty))
        case .superconductor(let cwd):
            activate(superconductorID)
            // Its CLI, which knows how to select a worktree by path. Not on
            // this app's PATH, so it is named outright.
            let home = FileManager.default.homeDirectoryForCurrentUser
            let sc = home.appendingPathComponent(".superconductor/bin/sc")
            guard FileManager.default.isExecutableFile(atPath: sc.path) else { return }
            let process = Process()
            process.executableURL = sc
            process.arguments = ["worktree", "open", cwd, "--activate"]
            // Somewhere for its output to go: a closed pipe is a broken one,
            // and a tool that cannot print its result may give up before it
            // has done the thing.
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch {
                Log.sessions.error("sc worktree open failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Brought forward through the workspace rather than asked to activate
    /// itself: from an app that is never active — every panel here is
    /// non-activating — a direct activation request is one macOS may
    /// quietly decline, while opening the app again is honoured whether or
    /// not it is running.
    @MainActor
    private static func activate(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Selecting a tab by tty: Terminal and iTerm2 both expose it, in their
    /// own dialects. The first time, macOS asks whether Codenotch may control
    /// the terminal; declining leaves the app merely brought forward.
    static func selectTabScript(bundleID: String, tty: String) -> String {
        switch bundleID {
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                tell w to select
                                tell t to select
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default:
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        }
    }

    @MainActor
    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.sessions.error("select tab failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// The real thing: the kernel's process table, and the running-app list.
struct LiveProcesses: ProcessInspecting {
    func parent(of pid: Int32) -> Int32? {
        guard let info = Self.info(pid) else { return nil }
        return info.kp_eproc.e_ppid
    }

    func tty(of pid: Int32) -> String? {
        guard let info = Self.info(pid) else { return nil }
        let device = info.kp_eproc.e_tdev
        // NODEV: no controlling terminal.
        guard device != UInt32.max, let name = devname(dev_t(device), S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    func bundleID(of pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func info(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
