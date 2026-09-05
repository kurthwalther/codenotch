import XCTest
@testable import Codenotch

/// The conversation card's plumbing: which road a reply takes, which agent
/// super.engineering is told to send to, and what the card reads.
@MainActor
final class ConversationTests: XCTestCase {
    private func session(locator: SessionLocator?) -> AgentSession {
        AgentSession(id: "claude.1", name: "s", detail: "Terminal · p", state: .idle,
                     waitingFor: nil, since: Date(), locator: locator)
    }

    func testTheRoadFollowsTheHost() {
        let sc = SessionFocusTests.Fake(tree: [1: (2, "/dev/ttys001", nil), 2: (1, nil, SessionFocus.superconductorID)])
        XCTAssertEqual(SessionReply.route(for: SessionLocator(pid: 1, cwd: "/p"), processes: sc),
                       .superconductor(cwd: "/p"))
        let term = SessionFocusTests.Fake(tree: [1: (2, "/dev/ttys001", nil), 2: (1, nil, "com.apple.Terminal")])
        XCTAssertEqual(SessionReply.route(for: SessionLocator(pid: 1, cwd: "/p"), processes: term),
                       .terminal(bundleID: "com.apple.Terminal", tty: "/dev/ttys001"))
        let code = SessionFocusTests.Fake(tree: [1: (2, nil, nil), 2: (1, nil, "com.microsoft.VSCode")])
        XCTAssertEqual(SessionReply.route(for: SessionLocator(pid: 1, cwd: "/p"), processes: code), .clipboard)
        XCTAssertEqual(SessionReply.route(for: SessionLocator(), processes: SessionFocusTests.Fake()), .clipboard)
    }

    /// One Claude agent that can take a send: that one. Two, or none: no
    /// guessing.
    func testTheOneClaudeAgentIsTheTarget() {
        func listing(_ agents: [[String: Any]]) -> Data {
            try! JSONSerialization.data(withJSONObject: ["kind": "agents", "response": ["agents": agents]])
        }
        let claude: [String: Any] = ["stable_target_id": "terminal:abc", "provider_key": "claude",
                                     "capabilities": ["send": true]]
        let codex: [String: Any] = ["stable_target_id": "terminal:def", "provider_key": "codex",
                                    "capabilities": ["send": true]]
        let mute: [String: Any] = ["stable_target_id": "terminal:ghi", "provider_key": "claude",
                                   "capabilities": ["send": false]]
        XCTAssertEqual(SessionReply.pickTarget(fromAgentsJSON: listing([claude, codex, mute])), "terminal:abc")
        XCTAssertNil(SessionReply.pickTarget(fromAgentsJSON: listing([claude, claude])), "two: ambiguous")
        XCTAssertNil(SessionReply.pickTarget(fromAgentsJSON: listing([codex])))
        XCTAssertNil(SessionReply.pickTarget(fromAgentsJSON: Data("nonsense".utf8)))
    }

    func testTypedTextIsEscapedForAppleScript() {
        let script = SessionReply.typeIntoTerminalScript(
            bundleID: "com.apple.Terminal", tty: "/dev/ttys002", text: #"say "hi" \ bye"#)
        XCTAssertTrue(script.contains(#"do script "say \"hi\" \\ bye" in t"#))
        let iterm = SessionReply.typeIntoTerminalScript(bundleID: "com.googlecode.iterm2", tty: "/dev/ttys002", text: "x")
        XCTAssertTrue(iterm.contains(#"tell s to write text "x""#))
    }

    func testTheCardReadsAndRefreshes() {
        let conversation = Conversation(session: session(locator: SessionLocator(transcriptID: "t")))
        var turns = [TranscriptTurn(role: .user, text: "hi", at: nil)]
        conversation.reader = { _ in turns }
        conversation.load()
        XCTAssertEqual(conversation.turns.count, 1)
        turns.append(TranscriptTurn(role: .assistant, text: "hello", at: nil))
        conversation.load()
        XCTAssertEqual(conversation.turns.map(\.role), [.user, .assistant])
        XCTAssertFalse(conversation.isEmpty)
    }

    func testASessionWithoutATranscriptReadsNothing() {
        let conversation = Conversation(session: session(locator: nil))
        conversation.load()
        XCTAssertTrue(conversation.isEmpty)
    }

    func testAnEmptyDraftIsNotSent() async {
        let state = await SessionReply.send("   ", to: session(locator: SessionLocator(cwd: "/p")))
        XCTAssertEqual(state, .idle)
    }
}
