import Combine
import Foundation

/// A session's conversation as the card shows it: the last turns, refreshed
/// while the card is open so an answer arrives where the question was asked.
@MainActor
final class Conversation: ObservableObject {
    let session: AgentSession
    @Published private(set) var turns: [TranscriptTurn] = []
    /// What the session is doing now, kept current by the app so the card
    /// can say "working…" under the last turn while the answer is written.
    @Published var state: AgentSession.State
    /// What the reply field holds, and what became of the last send.
    @Published var draft = ""
    @Published var sendState: SendState = .idle

    enum SendState: Equatable {
        case idle
        /// The agent is mid-turn; the line goes the moment it is free.
        case waiting
        case sent(Date)
        case failed(String)
        /// No way to deliver to this session; the text is on the clipboard.
        case copied
    }

    /// Files to go with the line, by path — which is how Claude Code takes
    /// them, images included.
    @Published var attachments: [URL] = []

    /// The send in flight, so a wait for the agent can be called off.
    var dispatch: SessionReply.Dispatch?

    /// How many turns the card shows. Enough for the thread of it; the whole
    /// session lives in the tool that owns it.
    static let limit = 10

    /// Reads the turns; swapped out under test.
    var reader: (AgentSession) -> [TranscriptTurn] = { session in
        guard let id = session.locator?.transcriptID else { return [] }
        return ClaudeTranscript.lastTurns(sessionID: id, limit: Conversation.limit)
    }

    private var refresh: Timer?

    init(session: AgentSession) {
        self.session = session
        self.state = session.state
    }

    func load() {
        let fresh = reader(session)
        if fresh != turns { turns = fresh }
    }

    /// Re-read every second while open: a turn is appended to the transcript
    /// as each of its parts finishes, and the card should show it then.
    func startFollowing() {
        load()
        guard refresh == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refresh = timer
    }

    func stopFollowing() {
        refresh?.invalidate()
        refresh = nil
    }

    /// A transcript with nothing readable yet, or a session from a tool that
    /// keeps none.
    var isEmpty: Bool { turns.isEmpty }
}
