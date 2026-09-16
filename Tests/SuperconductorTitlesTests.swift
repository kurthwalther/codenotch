import XCTest
@testable import Codenotch

final class SuperconductorTitlesTests: XCTestCase {
    /// A real `~/.superconductor/session.json`, trimmed to the parts this
    /// reads. Unknown keys must not cost a title.
    private let file = """
    { "version": 3,
      "selections": [
        { "key": { "workspace_id": "w1", "worktree_name": "main" },
          "value": { "tabs": [], "active_tab": 0 } },
        { "key": { "workspace_id": "w2", "worktree_name": "main" },
          "value": { "active_tab": 1, "diff_scroll_top_index": 0, "tabs": [
            { "kind": "terminal", "preset_key": "claude", "provider_key": "claude",
              "session_id": "2d47d653", "title": "Queja Por Demora",
              "title_sc_owned": true, "somethingNew": 42 },
            { "kind": "api-chat", "provider_key": "claude",
              "session_id": "2aaad5f0", "title": "Verificación De Paridad" },
            { "kind": "terminal", "preset_key": "codex", "provider_key": "codex",
              "session_id": "0f1c", "title": "Codex" }
          ] } }
      ] }
    """

    private func titles(placeholders: Set<String> = []) -> SuperconductorTitles {
        SuperconductorTitles.parse(session: Data(file.utf8), placeholders: placeholders)
    }

    func testReadsTheTitleOfEveryTabInEveryWorkspace() {
        let titles = self.titles()
        XCTAssertEqual(titles.title(for: "2d47d653"), "Queja Por Demora")
        XCTAssertEqual(titles.title(for: "2aaad5f0"), "Verificación De Paridad")
    }

    func testSessionsWithNoTabKeepTheirOwnName() {
        XCTAssertNil(titles().title(for: "a-session-that-is-not-in-a-tab"))
        XCTAssertNil(titles().title(for: nil))
    }

    /// An untitled tab is named after the tool running in it, which in a list
    /// of Claude sessions names nothing. Those fall back to the tool's name.
    func testIgnoresTheToolNameAnUntitledTabCarries() {
        let titles = self.titles(placeholders: ["Claude Code", "Codex", "Terminal"])
        XCTAssertNil(titles.title(for: "0f1c"))
        XCTAssertEqual(titles.title(for: "2d47d653"), "Queja Por Demora")
    }

    func testPlaceholdersAreTheToolNamesFromSettings() {
        let settings = """
        { "default_tool": "claude", "font_size": 13,
          "tools": {
            "claude": { "name": "Claude Code", "command": "claude" },
            "codex":  { "name": "Codex", "command": "codex" },
            "broken": "not a dictionary"
          } }
        """
        XCTAssertEqual(SuperconductorTitles.placeholders(settings: Data(settings.utf8)),
                       ["Claude Code", "Codex"])
    }

    func testSurvivesAFileItDoesNotRecognise() {
        XCTAssertTrue(SuperconductorTitles.parse(session: Data("not json".utf8)).isEmpty)
        XCTAssertTrue(SuperconductorTitles.parse(session: Data(#"{"selections": 7}"#.utf8)).isEmpty)
        XCTAssertTrue(SuperconductorTitles.parse(session: Data(#"{}"#.utf8)).isEmpty)
        XCTAssertTrue(SuperconductorTitles.placeholders(settings: Data("not json".utf8)).isEmpty)
    }

    func testAnEmptyTitleIsNoTitle() {
        let file = #"{"selections":[{"value":{"tabs":[{"session_id":"x","title":"   "}]}}]}"#
        XCTAssertNil(SuperconductorTitles.parse(session: Data(file.utf8)).title(for: "x"))
    }

    /// The whole point: the tooltip shows what the tab is called, not the name
    /// Claude Code derived from the folder.
    @MainActor
    func testTheTabTitleReplacesTheDerivedName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pid = ProcessInfo.processInfo.processIdentifier   // alive, by definition
        try Data("""
        { "pid": \(pid), "sessionId": "2d47d653", "cwd": "/Users/vinz/superconductor/agents/Developer",
          "entrypoint": "cli", "name": "developer-db", "nameSource": "derived", "status": "idle" }
        """.utf8).write(to: directory.appendingPathComponent("\(pid).json"))

        let named = ClaudeSessionMonitor.read(directory: directory, titles: titles())
        XCTAssertEqual(named.first?.name, "Queja Por Demora")
        XCTAssertEqual(named.first?.detail, "Terminal · Developer")

        // No super.engineering on this Mac, or a session it does not hold.
        let plain = ClaudeSessionMonitor.read(directory: directory)
        XCTAssertEqual(plain.first?.name, "developer-db")
    }
}
