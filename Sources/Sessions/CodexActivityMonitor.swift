import AppKit
import Combine
import Foundation

/// Reports whether Codex is mid-turn.
///
/// Codex publishes no status field — no equivalent of Claude Code's `status` or
/// Cursor's `unfinishedRunAt`. What it does do is append to a thread's rollout
/// log continuously while a turn runs, so a rollout written moments ago means
/// work is happening now.
///
/// **That is a heuristic, and it is labelled as one.** It cannot tell a turn
/// that is thinking from one that finished a second ago, so it errs short: the
/// ring stops spinning `staleAfter` seconds after the last write rather than
/// claiming activity it cannot see. If Codex grows a real status field this
/// should be replaced by it.
@MainActor
final class CodexActivityMonitor: ObservableObject, AgentActivityMonitor {
    @Published private(set) var sessions: [AgentSession] = []
    var sessionsPublisher: AnyPublisher<[AgentSession], Never> { $sessions.eraseToAnyPublisher() }

    private let stateStore: URL
    private let desktopStore: URL
    private let interval: TimeInterval
    /// How long after the last write a turn is still considered in flight.
    private let staleAfter: TimeInterval
    private var timer: Timer?

    init(
        stateStore: URL = CodexStore.stateURL,
        desktopStore: URL = CodexStore.desktopStoreURL,
        interval: TimeInterval = 2,
        staleAfter: TimeInterval = 8
    ) {
        self.stateStore = stateStore
        self.desktopStore = desktopStore
        self.interval = interval
        self.staleAfter = staleAfter
    }

    func start() {
        rescan()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func rescan() {
        let found = Self.read(stateStore: stateStore, desktopStore: desktopStore,
                              staleAfter: staleAfter)
        guard found != sessions else { return }
        sessions = found
    }

    static func read(stateStore: URL, desktopStore: URL,
                     staleAfter: TimeInterval, now: Date = Date()) -> [AgentSession] {
        // Both surfaces, because "Codex" is two programs that record their work
        // in different places: the CLI and the VS Code extension append to a
        // rollout, and the desktop app writes to its own catalogue. Whichever
        // moved last is the one that is working.
        var candidates: [(id: String, name: String, at: Date, locator: SessionLocator?)] = []

        if let rollout = CodexStore.newestRollout(in: stateStore),
           let modified = (try? FileManager.default
               .attributesOfItem(atPath: rollout.path))?[.modificationDate] as? Date {
            // The CLI leaves no process behind to find; the folder it was
            // working in is the most the rollout can say.
            let cwd = rolloutWorkingDirectory(rollout)
            candidates.append((id: "codex.\(rollout.lastPathComponent)",
                               name: "Codex", at: modified,
                               locator: cwd.map { SessionLocator(cwd: $0) }))
        }
        if let desktop = CodexStore.newestDesktopThread(in: desktopStore) {
            candidates.append((id: "codex.desktop", name: desktop.title,
                               at: desktop.updatedAt,
                               locator: SessionLocator(appBundleID: "com.openai.codex")))
        }

        guard let newest = candidates.max(by: { $0.at < $1.at }),
              var session = session(id: newest.id, name: newest.name,
                                    modified: newest.at, staleAfter: staleAfter, now: now)
        else { return [] }
        session.locator = newest.locator
        return [session]
    }

    /// The `cwd` a rollout opens with, from its first line. Read leniently:
    /// the file is another program's, and a shape we do not recognise costs
    /// nothing but the click.
    static func rolloutWorkingDirectory(_ rollout: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: rollout) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 8192),
              let text = String(data: head, encoding: .utf8),
              let line = text.split(separator: "\n", maxSplits: 1).first,
              let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        else { return nil }
        let payload = json["payload"] as? [String: Any]
        return (payload?["cwd"] as? String) ?? (json["cwd"] as? String)
    }

    /// Only work recorded within the window counts. Anything older is a
    /// finished turn, and reporting it as work in progress would be a guess
    /// dressed as a fact.
    static func session(
        id: String, name: String, modified: Date, staleAfter: TimeInterval, now: Date
    ) -> AgentSession? {
        guard now.timeIntervalSince(modified) <= staleAfter else { return nil }
        return AgentSession(
            id: id,
            name: name,
            detail: "Working",
            state: .busy,
            waitingFor: nil,
            since: modified
        )
    }
}
