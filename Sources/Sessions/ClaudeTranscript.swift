import Foundation

/// One turn of a conversation, as much of it as a card can show.
struct TranscriptTurn: Equatable {
    enum Role: Equatable { case user, assistant }
    let role: Role
    let text: String
    let at: Date?
}

/// Claude Code's transcript of a session, read from the end.
///
/// Every session is a JSON-lines file under `~/.claude/projects/<folder>/`,
/// named by the session id, one record per line: user turns, assistant turns,
/// tool calls and their results, and housekeeping. Only the turns with words
/// in them are wanted, and only the last few — so the file is read from its
/// tail, never whole; a long session runs to tens of megabytes.
enum ClaudeTranscript {
    static var projectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    /// Where the transcript is, found by its name rather than by working out
    /// the folder's: the folder is the working directory with its separators
    /// mangled, and the rule for that is Claude Code's to change.
    static func url(for sessionID: String, in projects: URL = projectsDirectory) -> URL? {
        guard !sessionID.isEmpty, !sessionID.contains("/"),
              let folders = try? FileManager.default.contentsOfDirectory(
                  at: projects, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return nil }
        let name = "\(sessionID).jsonl"
        return folders.lazy
            .map { $0.appendingPathComponent(name) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The last `limit` turns with words in them, oldest first.
    static func lastTurns(sessionID: String, limit: Int = 8,
                          tailBytes: Int = 512 * 1024,
                          in projects: URL = projectsDirectory) -> [TranscriptTurn] {
        guard let url = url(for: sessionID, in: projects) else { return [] }
        return lastTurns(of: url, limit: limit, tailBytes: tailBytes)
    }

    static func lastTurns(of url: URL, limit: Int = 8, tailBytes: Int = 512 * 1024) -> [TranscriptTurn] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty
        else { return [] }
        return turns(fromTail: data, partialFirstLine: start > 0, limit: limit)
    }

    /// Turns out of a run of lines. When the run started mid-file its first
    /// line is a fragment and is thrown away.
    static func turns(fromTail data: Data, partialFirstLine: Bool, limit: Int) -> [TranscriptTurn] {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if partialFirstLine, !lines.isEmpty { lines.removeFirst() }
        var found: [TranscriptTurn] = []
        for line in lines.reversed() {
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let turn = turn(from: json) else { continue }
            found.append(turn)
            if found.count >= limit { break }
        }
        return found.reversed()
    }

    /// A turn with words in it, or nil for anything else on the line: tool
    /// calls, tool results, thinking, summaries, housekeeping.
    static func turn(from json: [String: Any]) -> TranscriptTurn? {
        let role: TranscriptTurn.Role
        switch json["type"] as? String {
        case "user":      role = .user
        case "assistant": role = .assistant
        default:          return nil
        }
        guard let message = json["message"] as? [String: Any] else { return nil }
        let text: String
        if let plain = message["content"] as? String {
            text = plain
        } else if let blocks = message["content"] as? [[String: Any]] {
            text = blocks
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        } else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let at = (json["timestamp"] as? String).flatMap(Self.parseDate)
        return TranscriptTurn(role: role, text: trimmed, at: at)
    }

    /// The start of a turn, as one line for a small card: markdown marks
    /// dropped, whitespace folded, cut at a word.
    static func preview(_ text: String, limit: Int = 140) -> String {
        var line = text
        for mark in ["**", "__", "`", "#"] {
            line = line.replacingOccurrences(of: mark, with: "")
        }
        line = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard line.count > limit else { return line }
        let cut = line.index(line.startIndex, offsetBy: limit)
        let head = line[..<cut]
        let atWord = head.lastIndex(of: " ").map { head[..<$0] } ?? head
        return atWord + "…"
    }

    private static let dates: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let wholeSecondDates: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ text: String) -> Date? {
        dates.date(from: text) ?? wholeSecondDates.date(from: text)
    }
}
