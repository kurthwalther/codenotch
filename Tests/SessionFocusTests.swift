import XCTest
@testable import Codenotch

/// Where a click on a session goes, decided against a made-up process table.
final class SessionFocusTests: XCTestCase {
    /// A process tree: pid → (parent, tty, bundle id), plus which apps run.
    struct Fake: ProcessInspecting {
        var tree: [Int32: (parent: Int32, tty: String?, app: String?)] = [:]
        var running: Set<String> = []
        func parent(of pid: Int32) -> Int32? { tree[pid]?.parent }
        func tty(of pid: Int32) -> String? { tree[pid]?.tty }
        func bundleID(of pid: Int32) -> String? { tree[pid]?.app }
        func isRunning(bundleID: String) -> Bool { running.contains(bundleID) }
    }

    private let cwd = "/Users/me/project"

    /// claude → bash → super.engineering, the way it actually runs here.
    func testASessionUnderSuperconductorSelectsItsWorktree() {
        let processes = Fake(tree: [
            3374: (3292, "/dev/ttys002", nil),
            3292: (720, "/dev/ttys002", nil),
            720:  (1, nil, SessionFocus.superconductorID)
        ])
        let locator = SessionLocator(pid: 3374, cwd: cwd, entrypoint: "cli")
        XCTAssertEqual(SessionFocus.destination(for: locator, processes: processes),
                       .superconductor(cwd: cwd))
    }

    func testASessionInTerminalSelectsItsTabByTty() {
        let processes = Fake(tree: [
            10: (9, "/dev/ttys004", nil),
            9:  (8, "/dev/ttys004", nil),
            8:  (1, nil, "com.apple.Terminal")
        ])
        XCTAssertEqual(SessionFocus.destination(for: SessionLocator(pid: 10, cwd: cwd), processes: processes),
                       .terminalTab(bundleID: "com.apple.Terminal", tty: "/dev/ttys004"))
    }

    /// Launched by an editor's extension, the folder is the way back to the
    /// window: opening it again lands on the one that already has it.
    func testASessionUnderAnEditorOpensItsFolder() {
        let processes = Fake(tree: [
            20: (19, nil, nil),
            19: (18, nil, nil),
            18: (1, nil, "com.microsoft.VSCode")
        ])
        XCTAssertEqual(SessionFocus.destination(for: SessionLocator(pid: 20, cwd: cwd, entrypoint: "claude-vscode"),
                                                processes: processes),
                       .folder(bundleID: "com.microsoft.VSCode", cwd: cwd))
    }

    func testAnUnknownHostIsJustBroughtForward() {
        let processes = Fake(tree: [
            30: (29, "/dev/ttys001", nil),
            29: (1, nil, "com.mitchellh.ghostty")
        ])
        XCTAssertEqual(SessionFocus.destination(for: SessionLocator(pid: 30, cwd: cwd), processes: processes),
                       .app(bundleID: "com.mitchellh.ghostty"))
    }

    /// A folder alone is enough while super.engineering is running — a Codex
    /// rollout knows no more than that.
    func testAFolderAloneGoesToSuperconductorWhenItIsRunning() {
        let running = Fake(running: [SessionFocus.superconductorID])
        XCTAssertEqual(SessionFocus.destination(for: SessionLocator(cwd: cwd), processes: running),
                       .superconductor(cwd: cwd))
        XCTAssertNil(SessionFocus.destination(for: SessionLocator(cwd: cwd), processes: Fake()))
    }

    func testAnAppAloneIsBroughtForward() {
        XCTAssertEqual(SessionFocus.destination(for: SessionLocator(appBundleID: "com.openai.codex"), processes: Fake()),
                       .app(bundleID: "com.openai.codex"))
        XCTAssertNil(SessionFocus.destination(for: SessionLocator(), processes: Fake()))
    }

    /// A pid whose ancestry is all shells and no app falls through to the
    /// folder and app rules rather than pointing at nothing.
    func testAnOrphanedProcessFallsThrough() {
        let processes = Fake(tree: [40: (1, "/dev/ttys009", nil)], running: [SessionFocus.superconductorID])
        XCTAssertEqual(SessionFocus.destination(for: SessionLocator(pid: 40, cwd: cwd), processes: processes),
                       .superconductor(cwd: cwd))
    }

    func testTheTerminalScriptsNameTheTty() {
        XCTAssertTrue(SessionFocus.selectTabScript(bundleID: "com.apple.Terminal", tty: "/dev/ttys002")
            .contains("tty of t is \"/dev/ttys002\""))
        XCTAssertTrue(SessionFocus.selectTabScript(bundleID: "com.googlecode.iterm2", tty: "/dev/ttys002")
            .contains("tty of s is \"/dev/ttys002\""))
    }

    /// The real inspector, on this very process: it has a parent, and this
    /// test bundle's host is an app.
    func testTheLiveInspectorSeesThisProcess() {
        let live = LiveProcesses()
        let me = ProcessInfo.processInfo.processIdentifier
        XCTAssertNotNil(live.parent(of: me))
        XCTAssertNotNil(SessionFocus.hostingApp(of: me, processes: live))
    }
}
