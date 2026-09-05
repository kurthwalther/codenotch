import Combine
import Foundation

/// Something an agent did that is worth a word: it finished, or it stopped
/// to wait on you.
struct SessionNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case finished
        case waiting
    }

    let id: String
    let session: AgentSession
    let kind: Kind
    /// The start of what it last said — or what it is waiting for.
    let preview: String
    let at: Date

    var title: String {
        switch kind {
        case .finished: return "\(session.name) · done"
        case .waiting:  return "\(session.name) · needs you"
        }
    }
}

/// Watches every session's state and raises a notice when one crosses the
/// line from working to done, or to waiting. Pure where it can be, so the
/// crossings can be pinned without a clock.
@MainActor
final class SessionNoticeCenter: ObservableObject {
    @Published private(set) var notices: [SessionNotice] = []

    var enabled = true
    /// Reads the agent's last words; swapped out under test.
    var lastWords: (AgentSession) -> String? = { session in
        guard let id = session.locator?.transcriptID else { return nil }
        return ClaudeTranscript.lastTurns(sessionID: id, limit: 3)
            .last { $0.role == .assistant }
            .map { ClaudeTranscript.preview($0.text) }
    }

    private var statesBefore: [String: AgentSession.State] = [:]
    private var lastPreview: [String: String] = [:]

    /// What crossed a line between the last look and this one.
    static func crossings(from before: [String: AgentSession.State],
                          to sessions: [AgentSession]) -> [(AgentSession, SessionNotice.Kind)] {
        sessions.compactMap { session in
            guard let was = before[session.id], was != session.state else { return nil }
            switch (was, session.state) {
            case (.busy, .idle):       return (session, .finished)
            case (_, .waiting):        return (session, .waiting)
            default:                   return nil
            }
        }
    }

    func observe(_ sessions: [String: [AgentSession]], now: Date = Date()) {
        let all = sessions.values.flatMap { $0 }
        var states: [String: AgentSession.State] = [:]
        for session in all { states[session.id] = session.state }
        defer { statesBefore = states }
        settle(sessions)
        guard enabled else { return }

        for (session, kind) in Self.crossings(from: statesBefore, to: all) {
            let preview: String
            switch kind {
            case .waiting:
                preview = session.waitingFor.map { ClaudeTranscript.preview($0) }
                    ?? lastWords(session) ?? "Waiting on you"
            case .finished:
                preview = lastWords(session) ?? "Finished"
            }
            // The same words twice is the same notice: a session that flickers
            // through idle mid-turn must not knock twice.
            let key = "\(session.id)#\(kind == .waiting ? "w" : "f")"
            guard lastPreview[key] != preview else { continue }
            lastPreview[key] = preview
            let notice = SessionNotice(id: "\(session.id)@\(now.timeIntervalSince1970)",
                                       session: session, kind: kind, preview: preview, at: now)
            // One notice per session at a time: the newer replaces the older.
            notices.removeAll { $0.session.id == session.id }
            notices.append(notice)
        }
    }

    func dismiss(_ id: String) {
        notices.removeAll { $0.id == id }
    }

    /// Drops what has been up longer than `lifetime`, unless told to hold.
    /// A note that an agent needs you is not on the clock: it stays until
    /// you answer it, open it, or the session stops waiting.
    func expire(after lifetime: TimeInterval, now: Date = Date(), holding: Bool) {
        guard !holding else { return }
        notices.removeAll { $0.kind == .finished && now.timeIntervalSince($0.at) > lifetime }
    }

    /// A session that stopped waiting takes its "needs you" note with it.
    func settle(_ sessions: [String: [AgentSession]]) {
        let waiting = Set(sessions.values.flatMap { $0 }.filter { $0.state == .waiting }.map(\.id))
        notices.removeAll { $0.kind == .waiting && !waiting.contains($0.session.id) }
    }
}
