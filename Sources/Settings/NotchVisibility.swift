import Foundation

/// How much of itself the notch shows when you are not using it.
///
/// Three states rather than the two that get asked for, because the default is
/// neither: at rest the notch is already a small pill that opens on contact.
/// Offering only "always" and "hidden" would quietly delete the behaviour the
/// app was designed around.
enum NotchVisibility: String, CaseIterable, Identifiable {
    /// Pinned open. The readings are always on screen.
    case alwaysShow
    /// Open while any agent session exists, a pill when none does. Stored as
    /// "auto": the name on screen is Smart, but a rename of the raw value
    /// would silently reset everyone who had chosen it.
    case auto
    /// A pill at the edge that unfolds when the pointer reaches it. The default.
    case onHover
    /// Nothing on screen at all.
    case hidden

    var id: String { rawValue }

    /// What Auto counts as reason to be open.
    enum AutoScope: String, CaseIterable, Identifiable {
        /// Any session at all, idle or waiting included.
        case session
        /// Only while some agent is busy.
        case working

        var id: String { rawValue }

        var title: String {
            switch self {
            case .session: return "A session is open"
            case .working: return "An agent is working"
            }
        }

        func opens(_ sessions: [String: [AgentSession]]) -> Bool {
            switch self {
            case .session: return sessions.values.contains { !$0.isEmpty }
            case .working: return sessions.values.contains { $0.contains { $0.state == .busy } }
            }
        }
    }

    var title: String {
        switch self {
        case .alwaysShow: return "Always show"
        case .auto:       return "Smart"
        case .onHover:    return "Show on hover"
        case .hidden:     return "Hide"
        }
    }

    var explanation: String {
        switch self {
        case .alwaysShow:
            return "The notch stays open with every reading visible, at full "
                 + "size — it never settles."
        case .auto:
            return "Open like Always show while any agent session exists; a "
                 + "pill at the edge, like Show on hover, when none does. "
                 + "The only mode that settles: left alone, it draws itself "
                 + "in and dims."
        case .onHover:
            return "A small pill at the screen edge that opens when you reach it."
        case .hidden:
            // Said here because a hidden notch is also a hidden way back in.
            return "Nothing on screen. Open Codenotch again from Applications "
                 + "to bring these settings back."
        }
    }
}
