import Foundation

/// Pure rules shared by Dock fusion filtering, sizing, and keyboard navigation.
enum FusionDisplayPolicy {
    struct Candidate {
        let id: String
        let appKey: String
        let isFocused: Bool
        let isAllowedOnRight: Bool
    }

    static let recentLifetime: TimeInterval = 5 * 60
    static let recentLimit = 2

    static func recentWindowIDs(
        from candidates: [Candidate],
        focusedAt: [String: Date],
        minimumWindowCount: Int,
        now: Date
    ) -> Set<String> {
        let counts = Dictionary(grouping: candidates, by: \.appKey).mapValues(\.count)
        let eligible = candidates.filter { candidate in
            guard candidate.isAllowedOnRight,
                  counts[candidate.appKey, default: 0] < minimumWindowCount else { return false }
            guard let date = focusedAt[candidate.id] else { return false }
            return candidate.isFocused || (date <= now && now.timeIntervalSince(date) <= recentLifetime)
        }
        let sorted = eligible.sorted {
            if $0.isFocused != $1.isFocused { return $0.isFocused }
            return (focusedAt[$0.id] ?? .distantPast) > (focusedAt[$1.id] ?? .distantPast)
        }
        return Set(sorted.prefix(recentLimit).map(\.id))
    }

    static func displayCount(appKeys: [String], collapseThreshold: Int) -> Int {
        let counts = Dictionary(grouping: appKeys, by: { $0 }).mapValues(\.count)
        return counts.values.reduce(0) { $0 + ($1 >= collapseThreshold ? 1 : $1) }
    }
}
