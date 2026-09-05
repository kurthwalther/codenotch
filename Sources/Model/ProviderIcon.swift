import Foundation

/// A symbol to draw in a provider's ring instead of its logo, chosen per
/// provider in Settings. Five, all about the same thing from different
/// angles, so any one of them still reads as "an AI" at glance size.
struct ProviderIcon: Identifiable, Equatable {
    let symbol: String
    let title: String

    var id: String { symbol }

    static let choices: [ProviderIcon] = [
        ProviderIcon(symbol: "apple.intelligence", title: "Intelligence"),
        ProviderIcon(symbol: "sparkles", title: "Sparkles"),
        ProviderIcon(symbol: "brain", title: "Brain"),
        ProviderIcon(symbol: "atom", title: "Atom"),
        ProviderIcon(symbol: "wand.and.stars", title: "Wand")
    ]

    /// Only symbols on the list are honoured: a name that is not one of
    /// them falls back to the logo rather than to a blank.
    static func symbol(for name: String?) -> String? {
        guard let name, choices.contains(where: { $0.symbol == name }) else { return nil }
        return name
    }
}
