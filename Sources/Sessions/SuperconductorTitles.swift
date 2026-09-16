import Foundation

/// The names super.engineering gives the tabs it runs agent sessions in.
///
/// Claude Code names a session after its folder plus two random characters —
/// "developer-2c" — which says where it runs and nothing about what it is
/// doing. super.engineering titles the same conversation from its contents
/// ("Queja Por Demora") and puts that on the tab, so that is the name the
/// person already knows the session by. Where both exist, the tab's title wins.
///
/// The join is on Claude Code's own `sessionId`, which super.engineering stores
/// beside the title. Only Claude carries that id through to `SessionLocator`
/// today, so Cursor and Codex sessions keep their own names.
///
/// Read from another app's file, on another app's release schedule: every field
/// is optional here, and a shape this does not recognise costs a title, never a
/// session.
struct SuperconductorTitles: Equatable {
    private let bySessionID: [String: String]

    init(bySessionID: [String: String] = [:]) {
        self.bySessionID = bySessionID
    }

    var isEmpty: Bool { bySessionID.isEmpty }

    func title(for sessionID: String?) -> String? {
        guard let sessionID else { return nil }
        return bySessionID[sessionID]
    }

    /// Tabs live at `selections[].value.tabs[]`, each one carrying the agent
    /// session it holds (`session_id`) and what the tab is called.
    static func parse(session data: Data, placeholders: Set<String> = []) -> SuperconductorTitles {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let selections = root["selections"] as? [[String: Any]]
        else { return SuperconductorTitles() }

        var titles: [String: String] = [:]
        for selection in selections {
            let value = selection["value"] as? [String: Any]
            for tab in (value?["tabs"] as? [[String: Any]]) ?? [] {
                guard let id = tab["session_id"] as? String,
                      let title = (tab["title"] as? String)?
                          .trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty,
                      !placeholders.contains(title)
                else { continue }
                titles[id] = title
            }
        }
        return SuperconductorTitles(bySessionID: titles)
    }

    /// A tab that has not been titled yet is called after the tool running in
    /// it — "Claude Code", "Codex", "Terminal" — which in a list of Claude
    /// sessions names nothing, and is worse than the folder name it would be
    /// replacing. Those names are read out of the same app's settings rather
    /// than hardcoded, so a tool added after this was written is still caught.
    static func placeholders(settings data: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tools = root["tools"] as? [String: Any]
        else { return [] }
        return Set(tools.values.compactMap { ($0 as? [String: Any])?["name"] as? String })
    }
}

/// Enough of a file to tell whether it is worth reading again.
struct FileStamp: Equatable {
    let modified: Date?
    let size: Int?

    init(of url: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        modified = attributes?[.modificationDate] as? Date
        size = (attributes?[.size] as? NSNumber)?.intValue
    }
}

/// The titles as they are right now, parsed only when the file has changed.
///
/// `ClaudeSessionMonitor.rescan` runs on a five second timer and on every write
/// to Claude Code's session directory, while the tab file is 25KB of JSON that
/// changes only when a tab is opened, closed, renamed or switched to. The stamp
/// skips the parse the rest of the time.
///
/// A rename therefore shows up within one rescan rather than instantly. That is
/// deliberate: `~/.superconductor` is written to constantly by other parts of
/// that app, so watching it would mean waking for events that have nothing to
/// do with titles, to save a delay nobody is waiting on — super.engineering
/// only titles a conversation once, seconds into it.
final class SuperconductorTitleSource {
    static let sessionURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".superconductor/session.json")
    static let settingsURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".superconductor/settings.json")

    private let sessionURL: URL
    private let settingsURL: URL

    private var titles = SuperconductorTitles()
    private var titlesStamp: FileStamp?
    private var placeholders: Set<String> = []
    private var placeholdersStamp: FileStamp?

    init(sessionURL: URL = SuperconductorTitleSource.sessionURL,
         settingsURL: URL = SuperconductorTitleSource.settingsURL) {
        self.sessionURL = sessionURL
        self.settingsURL = settingsURL
    }

    func current() -> SuperconductorTitles {
        let settingsStamp = FileStamp(of: settingsURL)
        if settingsStamp != placeholdersStamp {
            placeholdersStamp = settingsStamp
            placeholders = (try? Data(contentsOf: settingsURL))
                .map(SuperconductorTitles.placeholders) ?? []
            titlesStamp = nil   // the set that filters them changed; parse again
        }

        let sessionStamp = FileStamp(of: sessionURL)
        if sessionStamp != titlesStamp {
            titlesStamp = sessionStamp
            titles = (try? Data(contentsOf: sessionURL))
                .map { SuperconductorTitles.parse(session: $0, placeholders: placeholders) }
                ?? SuperconductorTitles()
        }
        return titles
    }
}
