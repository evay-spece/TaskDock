import Foundation

@main
struct ReleaseDefaultsSelfTest {
    static func main() throws {
        let suite = "taskdock.release-defaults-selftest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure() }
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("[]".utf8), forKey: "taskdock.favoriteApps")
        defaults.set(Data("personal-folders".utf8), forKey: "taskdock.favoriteFolders")
        ReleaseDefaults101.applyIfNeeded(to: defaults)

        let data = try XCTUnwrap(defaults.data(forKey: "taskdock.favoriteApps"))
        let favorites = try JSONDecoder().decode([FavoriteApp].self, from: data)
        precondition(favorites.map(\.id) == [
            "com.apple.finder", "com.apple.Safari", "com.apple.iCal",
            "com.apple.reminders", "com.apple.Notes"
        ])
        precondition(defaults.string(forKey: "taskdock.layoutMode") == "taskbar")
        precondition(defaults.double(forKey: "taskdock.taskbarHeight") == 48)
        precondition(defaults.data(forKey: "taskdock.favoriteFolders") == Data("personal-folders".utf8))

        defaults.set(Data("user-reordered".utf8), forKey: "taskdock.favoriteApps")
        ReleaseDefaults101.applyIfNeeded(to: defaults)
        precondition(defaults.data(forKey: "taskdock.favoriteApps") == Data("user-reordered".utf8))
        print("RELEASE_DEFAULTS_OK")
    }
}

private func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "ReleaseDefaultsSelfTest", code: 1) }
    return value
}
