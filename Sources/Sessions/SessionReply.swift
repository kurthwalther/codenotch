import AppKit
import Foundation

/// Getting a line of text to a session, by whatever road its host offers.
///
/// super.engineering has a command that sends a prompt to an agent by id;
/// Terminal and iTerm2 take text typed into the tab on the session's tty;
/// anything else gets the text on the clipboard and the app in front, which
/// is one paste short of the same thing.
enum SessionReply {
    enum Route: Equatable {
        case superconductor(cwd: String)
        case terminal(bundleID: String, tty: String)
        case clipboard
    }

    static func route(for locator: SessionLocator, processes: ProcessInspecting) -> Route {
        switch SessionFocus.destination(for: locator, processes: processes) {
        case .superconductor(let cwd):          return .superconductor(cwd: cwd)
        case .terminalTab(let id, let tty):     return .terminal(bundleID: id, tty: tty)
        case .folder, .app, .none:              return .clipboard
        }
    }

    @MainActor
    static func send(_ text: String, to session: AgentSession) async -> Conversation.SendState {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, let locator = session.locator else { return .idle }
        switch route(for: locator, processes: LiveProcesses()) {
        case .superconductor(let cwd):
            do {
                try await sendThroughSuperconductor(line, cwd: cwd)
                return .sent(Date())
            } catch {
                Log.sessions.error("reply via sc failed: \(error.localizedDescription, privacy: .public)")
                return .failed(error.localizedDescription)
            }
        case .terminal(let id, let tty):
            var error: NSDictionary?
            NSAppleScript(source: typeIntoTerminalScript(bundleID: id, tty: tty, text: line))?
                .executeAndReturnError(&error)
            if let error {
                Log.sessions.error("reply via terminal failed: \(String(describing: error), privacy: .public)")
                return .failed("The terminal did not take it")
            }
            return .sent(Date())
        case .clipboard:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(line, forType: .string)
            SessionFocus.focus(session)
            return .copied
        }
    }

    // MARK: super.engineering

    struct ReplyError: LocalizedError {
        let errorDescription: String?
    }

    static var scURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".superconductor/bin/sc")
    }

    /// Lists the agents in the session's worktree and sends to the one that
    /// is Claude's. The app does not say which of its agents is which
    /// process, so a worktree with two Claude agents is left alone rather
    /// than guessed at.
    static func sendThroughSuperconductor(_ text: String, cwd: String) async throws {
        let listing = try await run(["agents", "list", "--output", "json", "--worktree", cwd])
        guard let target = pickTarget(fromAgentsJSON: listing) else {
            throw ReplyError(errorDescription: "Couldn't tell which agent to send to")
        }
        _ = try await run(["agent", "send", "--to", "id:\(target)", "--prompt", text,
                           "--worktree", cwd, "--output", "json"])
    }

    /// What the tool said went wrong, in its own JSON on standard output —
    /// which is where it puts it, exit code or no exit code. The one refusal
    /// worth translating is the feature being off in the app's settings.
    static func explain(_ output: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
              (json["kind"] as? String) == "cli_error",
              let error = json["error"] as? [String: Any]
        else { return nil }
        if (error["code"] as? String) == "feature_disabled" {
            return "Turn on Agent orchestration in super.engineering: Settings › Experimental."
        }
        return error["message"] as? String
    }

    /// The stable id of the one Claude agent listed, or nil when there is
    /// none or more than one that can take a send.
    static func pickTarget(fromAgentsJSON data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let agents = response["agents"] as? [[String: Any]]
        else { return nil }
        let claude = agents.filter { agent in
            (agent["provider_key"] as? String) == "claude"
                && ((agent["capabilities"] as? [String: Any])?["send"] as? Bool) == true
        }
        guard claude.count == 1 else { return nil }
        return claude[0]["stable_target_id"] as? String
    }

    static func run(_ arguments: [String]) async throws -> Data {
        let sc = scURL
        guard FileManager.default.isExecutableFile(atPath: sc.path) else {
            throw ReplyError(errorDescription: "super.engineering's command line tool is not installed")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = sc
            process.arguments = arguments
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.terminationHandler = { process in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let message = explain(data)
                        ?? (stderr?.isEmpty == false ? stderr : nil)
                        ?? "super.engineering refused (exit \(process.terminationStatus))"
                    continuation.resume(throwing: ReplyError(errorDescription: message))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    // MARK: Terminals

    /// Typed into the tab on this tty and entered, in each terminal's own
    /// dialect. Quotes and backslashes are escaped for AppleScript's string.
    static func typeIntoTerminalScript(bundleID: String, tty: String, text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        switch bundleID {
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                tell s to write text "\(escaped)"
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
                            do script "\(escaped)" in t
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        }
    }
}
