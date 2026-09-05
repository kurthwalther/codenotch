import Foundation

/// What the number under a ring says. The ring itself always draws the
/// fraction left; the number can repeat it, or answer the other question
/// people hover for — how long until it comes back.
enum CellLabel: String, CaseIterable, Identifiable {
    case percentLeft
    case timeToReset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .percentLeft: return "Percent left"
        case .timeToReset: return "Time to reset"
        }
    }
}
