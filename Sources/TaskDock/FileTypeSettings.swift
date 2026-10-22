import Foundation

struct FileTypeEntry: Codable, Equatable {
    var id: String
    var title: String
    var baseName: String
    var fileExtension: String
    var enabled: Bool

    var isBuiltIn: Bool { NewFileKind(rawValue: id) != nil }
}

enum FileTypeSettings {
    static let domain = "com.taskdock.finder.settings"
    static let key = "fileTypesV1"
    static let enabledKey = "rightClickFeatureEnabledV1"
    static let entryVisibleKey = "rightClickSettingsVisibleV1"

    static var isEnabled: Bool {
        UserDefaults(suiteName: domain)?.bool(forKey: enabledKey) ?? false
    }

    static var isEntryVisible: Bool {
        UserDefaults(suiteName: domain)?.bool(forKey: entryVisibleKey) ?? false
    }

    static var defaults: [FileTypeEntry] {
        NewFileKind.allCases.map {
            FileTypeEntry(id: $0.rawValue, title: $0.title, baseName: $0.baseName,
                          fileExtension: $0.rawValue, enabled: true)
        }
    }

    static func migrateLegacyIfNeeded() {
        guard UserDefaults(suiteName: domain)?.data(forKey: key) == nil,
              let oldData = UserDefaults(suiteName: "com.chenhuang.NewFileRightClick.settings")?.data(forKey: key),
              let oldEntries = try? JSONDecoder().decode([FileTypeEntry].self, from: oldData) else { return }
        save(oldEntries)
    }

    static func load() -> [FileTypeEntry] {
        guard let data = UserDefaults(suiteName: domain)?.data(forKey: key),
              let saved = try? JSONDecoder().decode([FileTypeEntry].self, from: data) else {
            return defaults
        }
        var seen = Set<String>()
        let valid = saved.filter { item in
            guard !seen.contains(item.id), validExtension(item.fileExtension),
                  validName(item.title), validName(item.baseName) else { return false }
            seen.insert(item.id)
            return true
        }
        return valid
    }

    static func save(_ entries: [FileTypeEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults(suiteName: domain)?.set(data, forKey: key)
    }

    static func validExtension(_ value: String) -> Bool {
        let characters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return (1...16).contains(value.count) && value.unicodeScalars.allSatisfy { characters.contains($0) }
    }

    static func validName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 60 && !trimmed.contains("/") && !trimmed.contains(":")
    }
}
