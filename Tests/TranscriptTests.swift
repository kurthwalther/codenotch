import XCTest
@testable import Codenotch

/// Reading an agent's last words out of Claude Code's transcript, and
/// deciding when they are worth a note.
final class TranscriptTests: XCTestCase {
    private let lines = """
    {"type":"summary","summary":"earlier"}
    {"type":"user","message":{"role":"user","content":"Fix the tail please"},"timestamp":"2026-09-05T12:00:00.000Z"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm"},{"type":"tool_use","name":"Edit","input":{}}]},"timestamp":"2026-09-05T12:00:05.000Z"}
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]},"timestamp":"2026-09-05T12:00:06.000Z"}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done. **The tail** now swells:\\n\\n- one\\n- two"}]},"timestamp":"2026-09-05T12:00:09.500Z"}
    """

    func testOnlyTurnsWithWordsCount() {
        let turns = ClaudeTranscript.turns(fromTail: Data(lines.utf8), partialFirstLine: false, limit: 10)
        XCTAssertEqual(turns.map(\.role), [.user, .assistant])
        XCTAssertEqual(turns[0].text, "Fix the tail please")
        XCTAssertTrue(turns[1].text.hasPrefix("Done."))
        XCTAssertEqual(turns[1].at, ClaudeTranscript.parseDate("2026-09-05T12:00:09.500Z"))
    }

    func testAFragmentAtTheStartOfTheTailIsDropped() {
        let tail = "ent\":{\"content\":\"broken\"}}\n" + lines
        let turns = ClaudeTranscript.turns(fromTail: Data(tail.utf8), partialFirstLine: true, limit: 10)
        XCTAssertEqual(turns.count, 2)
    }

    func testTheLimitKeepsTheNewest() {
        let turns = ClaudeTranscript.turns(fromTail: Data(lines.utf8), partialFirstLine: false, limit: 1)
        XCTAssertEqual(turns.map(\.role), [.assistant])
    }

    func testThePreviewIsOneCleanLine() {
        XCTAssertEqual(ClaudeTranscript.preview("Done. **The tail** now swells:\n\n- one\n- two"),
                       "Done. The tail now swells: - one - two")
        let long = String(repeating: "word ", count: 60)
        let cut = ClaudeTranscript.preview(long, limit: 40)
        XCTAssertTrue(cut.hasSuffix("…"))
        XCTAssertLessThanOrEqual(cut.count, 42)
    }

    func testTheTranscriptIsFoundByItsName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("projects-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("-Users-me-some-project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("abc-123.jsonl")
        try lines.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(ClaudeTranscript.url(for: "abc-123", in: root)?.resolvingSymlinksInPath(),
                       file.resolvingSymlinksInPath())
        XCTAssertNil(ClaudeTranscript.url(for: "missing", in: root))
        XCTAssertNil(ClaudeTranscript.url(for: "../etc", in: root), "no wandering")
        // A tail long enough for the last line and a fragment of the one
        // before it: the fragment goes, the last line is read whole.
        let turns = ClaudeTranscript.lastTurns(sessionID: "abc-123", limit: 8, tailBytes: 300, in: root)
        XCTAssertEqual(turns.map(\.role), [.assistant], "read from the tail, a fragment dropped")
    }
}

/// When a session's change of state is worth a note.
@MainActor
final class SessionNoticeTests: XCTestCase {
    private func session(_ id: String, _ state: AgentSession.State, waitingFor: String? = nil) -> AgentSession {
        AgentSession(id: id, name: id, detail: "Terminal · proj", state: state,
                     waitingFor: waitingFor, since: Date(),
                     locator: SessionLocator(transcriptID: id))
    }

    func testFinishingAndWaitingCrossTheLine() {
        let before: [String: AgentSession.State] = ["a": .busy, "b": .busy, "c": .idle, "d": .idle]
        let now = [session("a", .idle), session("b", .waiting), session("c", .busy), session("d", .idle),
                   session("e", .idle)]
        let crossings = SessionNoticeCenter.crossings(from: before, to: now)
        XCTAssertEqual(crossings.map { $0.0.id }, ["a", "b"])
        XCTAssertEqual(crossings.map { $0.1 }, [.finished, .waiting])
    }

    func testANoticeCarriesTheAgentsLastWordsOnce() {
        let center = SessionNoticeCenter()
        var words = "All done, the tail swells now."
        center.lastWords = { _ in words }

        center.observe(["claude": [session("a", .busy)]])
        XCTAssertTrue(center.notices.isEmpty, "starting busy is not news")
        center.observe(["claude": [session("a", .idle)]])
        XCTAssertEqual(center.notices.count, 1)
        XCTAssertEqual(center.notices[0].title, "a · done")
        XCTAssertEqual(center.notices[0].preview, words)

        // Busy again and idle again with the same words: not twice.
        center.observe(["claude": [session("a", .busy)]])
        center.observe(["claude": [session("a", .idle)]])
        XCTAssertEqual(center.notices.count, 1)

        // New words, new note — replacing the old one for that session.
        words = "Second thing done."
        center.observe(["claude": [session("a", .busy)]])
        center.observe(["claude": [session("a", .idle)]])
        XCTAssertEqual(center.notices.count, 1)
        XCTAssertEqual(center.notices[0].preview, "Second thing done.")
    }

    func testWaitingSaysWhatItWaitsFor() {
        let center = SessionNoticeCenter()
        center.lastWords = { _ in "irrelevant" }
        center.observe(["claude": [session("a", .busy)]])
        center.observe(["claude": [session("a", .waiting, waitingFor: "Approve the edit to Foo.swift")]])
        XCTAssertEqual(center.notices[0].title, "a · needs you")
        XCTAssertEqual(center.notices[0].preview, "Approve the edit to Foo.swift")
    }

    func testSwitchedOffRaisesNothing() {
        let center = SessionNoticeCenter()
        center.enabled = false
        center.observe(["claude": [session("a", .busy)]])
        center.observe(["claude": [session("a", .idle)]])
        XCTAssertTrue(center.notices.isEmpty)
    }

    func testNoticesExpireUnlessHeld() {
        let center = SessionNoticeCenter()
        center.lastWords = { _ in "words" }
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        center.observe(["claude": [session("a", .busy)]], now: t0)
        center.observe(["claude": [session("a", .idle)]], now: t0)
        center.expire(after: 12, now: t0.addingTimeInterval(20), holding: true)
        XCTAssertEqual(center.notices.count, 1, "held by the pointer")
        center.expire(after: 12, now: t0.addingTimeInterval(20), holding: false)
        XCTAssertTrue(center.notices.isEmpty)
    }

    /// A "needs you" is not on the clock: it goes when you act, or when the
    /// session stops waiting on its own.
    func testANeedsYouStaysUntilItIsAnswered() {
        let center = SessionNoticeCenter()
        center.lastWords = { _ in "words" }
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        center.observe(["claude": [session("a", .busy)]], now: t0)
        center.observe(["claude": [session("a", .waiting, waitingFor: "Approve")]], now: t0)
        XCTAssertEqual(center.notices.first?.kind, .waiting)
        center.expire(after: 7, now: t0.addingTimeInterval(600), holding: false)
        XCTAssertEqual(center.notices.count, 1, "ten minutes on, still there")
        center.observe(["claude": [session("a", .busy)]], now: t0.addingTimeInterval(601))
        XCTAssertTrue(center.notices.isEmpty, "the session went back to work: the note goes")
    }

    func testTheCardSitsBesideTheNotch() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let usable = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let size = CGSize(width: 200, height: 80)
        let right = NoticeWindowController.frame(size: size, edge: .right, inset: 70, screen: screen, usable: usable)
        XCTAssertEqual(right.maxX, 1728 - 70, accuracy: 0.001)
        XCTAssertEqual(right.midY, screen.midY, accuracy: 0.001)
        let top = NoticeWindowController.frame(size: size, edge: .top, inset: 70, screen: screen, usable: usable)
        XCTAssertEqual(top.maxY, 1080 - 70, accuracy: 0.001)
        XCTAssertEqual(top.midX, screen.midX, accuracy: 0.001)
    }
}
