enum RecentAppHoverBehavior: String, CaseIterable {
    static let settingsKey = "taskdock.recentAppHoverBehaviorV1"
    case nameBubble
    case programList
}

enum RecentAppDisplayPolicy {
    static func visible<App>(
        from history: [App],
        excluding isFavorite: (App) -> Bool,
        limit: Int = 10
    ) -> [App] {
        Array(history.filter { !isFavorite($0) }.prefix(max(0, limit)))
    }
}
