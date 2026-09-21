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
    /// The same pill, but it waits to be clicked, and stays open until a
    /// click lands somewhere else — for a pointer that crosses the screen
    /// edge on its way to something else and should not set it off.
    case onClick
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

    /// A stable number for an NSMenuItem to carry. Tied to the stored value
    /// rather than to a position in `allCases`, so reordering the cases
    /// cannot quietly repoint a menu item at another mode.
    var menuTag: Int {
        switch self {
        case .alwaysShow: return 1
        case .auto:       return 2
        case .onHover:    return 3
        case .hidden:     return 4
        case .onClick:    return 5
        }
    }

    static func fromMenuTag(_ tag: Int) -> NotchVisibility? {
        allCases.first { $0.menuTag == tag }
    }

    var title: String {
        switch self {
        case .alwaysShow: return "Always show"
        case .auto:       return "Smart"
        case .onHover:    return "Show on hover"
        case .onClick:    return "Show on click"
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
        case .onClick:
            return "A small pill at the screen edge that opens when you click "
                 + "it, and folds away when you click anywhere else."
        case .hidden:
            // Said here because a hidden notch is also a hidden way back in.
            return "Nothing on screen. Open Codenotch again from Applications "
                 + "to bring these settings back."
        }
    }
}
