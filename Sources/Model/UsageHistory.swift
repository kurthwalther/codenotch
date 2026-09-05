import Foundation

/// Every reading taken, per metered window, kept for a day — the raw material
/// for "at this pace". The archive remembers only the last good reading, which
/// is enough to draw a ring and nothing like enough to say where it is heading.
struct UsageHistory {
    private let defaults: UserDefaults
    private let key = "usageHistory"

    /// Older than this and a reading says nothing about the present.
    static let retention: TimeInterval = 24 * 60 * 60
    /// A hard cap per window, so a busy day cannot grow the defaults without
    /// limit: a reading a minute for a day is 1,440, and the pace only ever
    /// looks at the last two hours of them.
    static let cap = 600

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(_ providerID: String, _ windowID: String) -> String {
        "\(providerID)/\(windowID)"
    }

    func load() -> [String: [UsagePace.Sample]] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [UsagePace.Sample]].self, from: data)
        else { return [:] }
        return decoded
    }

    private func save(_ all: [String: [UsagePace.Sample]]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }

    /// Adds one reading per metered window and drops what has aged out.
    func record(_ snapshot: ProviderSnapshot, at now: Date = Date()) {
        var all = load()
        let horizon = now.addingTimeInterval(-Self.retention)
        for window in snapshot.windows {
            guard let used = window.usedFraction else { continue }
            let k = Self.key(snapshot.id, window.id)
            var samples = (all[k] ?? []).filter { $0.at > horizon }
            samples.append(.init(at: now, used: used))
            if samples.count > Self.cap {
                samples.removeFirst(samples.count - Self.cap)
            }
            all[k] = samples
        }
        save(all)
    }

    func samples(providerID: String, windowID: String) -> [UsagePace.Sample] {
        load()[Self.key(providerID, windowID)] ?? []
    }

    /// The snapshot with a pace attached to every window that has one.
    func attachingPace(to snapshot: ProviderSnapshot, now: Date = Date()) -> ProviderSnapshot {
        let all = load()
        var result = snapshot
        result.pace = [:]
        for window in snapshot.windows {
            let samples = all[Self.key(snapshot.id, window.id)] ?? []
            if let pace = UsagePace.estimate(from: samples, now: now) {
                result.pace[window.id] = pace
            }
        }
        return result
    }

    /// Signing out forgets the readings, and the trail they left has to go
    /// with them.
    func forget(_ providerID: String) {
        var all = load()
        for k in all.keys where k.hasPrefix("\(providerID)/") {
            all.removeValue(forKey: k)
        }
        save(all)
    }
}
