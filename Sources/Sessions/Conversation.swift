import Combine
import Foundation

/// A session's conversation as the card shows it: the last turns, refreshed
/// while the card is open so an answer arrives where the question was asked.
@MainActor
final class Conversation: ObservableObject {
    let session: AgentSession
    @Published private(set) var turns: [TranscriptTurn] = []
    /// What the reply field holds, and what became of the last send.
    @Published var draft = ""
    @Published var sendState: SendState = .idle

    enum SendState: Equatable {
        case idle
        case sent(Date)
        case failed(String)
        /// No way to deliver to this session; the text is on the clipboard.
        case copied
    }

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
    }

    func load() {
        let fresh = reader(session)
        if fresh != turns { turns = fresh }
    }

    /// Re-read every couple of seconds while open: a turn is appended to the
    /// transcript as it finishes, and the card should show it then.
    func startFollowing() {
        load()
        guard refresh == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
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
