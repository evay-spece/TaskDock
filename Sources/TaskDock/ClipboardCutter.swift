import AppKit

// The marker distinguishes an intentional cut from an ordinary Finder copy.
enum ClipboardCutter {
    static let cutType = NSPasteboard.PasteboardType("com.taskdock.finder.cut")
    static let sourceType = NSPasteboard.PasteboardType("com.taskdock.finder.source-url")

    @discardableResult
    static func cut(_ urls: [URL]) -> Bool {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return false }
        let token = UUID().uuidString
        let items = files.map { url -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            item.setString(token, forType: cutType)
            item.setString(url.absoluteString, forType: sourceType)
            return item
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects(items)
    }

    static func cutFiles() -> [URL] {
        guard let items = NSPasteboard.general.pasteboardItems, !items.isEmpty,
              items.allSatisfy({ $0.string(forType: cutType) != nil }) else { return [] }
        let files = items.compactMap { item -> URL? in
            guard let raw = item.string(forType: sourceType), let url = URL(string: raw), url.isFileURL else { return nil }
            return url.standardizedFileURL
        }
        return files.count == items.count ? files : []
    }

    @discardableResult
    static func move(to folder: URL) throws -> [URL] {
        let files = cutFiles()
        guard !files.isEmpty else { throw MoveError.noCutFiles }
        let destination = folder.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MoveError.invalidDestination
        }
        let targets = files.map { destination.appendingPathComponent($0.lastPathComponent) }
        guard Set(targets.map(\.path)).count == targets.count else { throw MoveError.nameConflict }
        for (source, target) in zip(files, targets) {
            guard FileManager.default.fileExists(atPath: source.path) else { throw MoveError.sourceMissing(source.lastPathComponent) }
            guard !FileManager.default.fileExists(atPath: target.path) else { throw MoveError.nameConflict }
            guard target.path != source.path, !target.path.hasPrefix(source.path + "/") else { throw MoveError.invalidDestination }
        }
        try executeMoves(files: files, targets: targets)
        NSPasteboard.general.clearContents()
        return targets
    }

    static func executeMoves(files: [URL], targets: [URL],
                             moveItem: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws {
        var moved: [(URL, URL)] = []
        do {
            for (source, target) in zip(files, targets) {
                try moveItem(source, target)
                moved.append((source, target))
            }
        } catch {
            let originalError = error.localizedDescription
            var restored: [String] = []
            var unresolved: [String] = []
            for (source, target) in moved.reversed() {
                do {
                    try moveItem(target, source)
                    restored.append(source.path)
                } catch {
                    unresolved.append("\(source.lastPathComponent)\n目标位置：\(target.path)\n原位置：\(source.path)\n恢复失败：\(error.localizedDescription)")
                }
            }
            let pending = files.dropFirst(moved.count).map(\.path)
            throw MoveError.batchFailed(reason: originalError, restored: restored, unresolved: unresolved, pending: pending)
        }
    }

    enum MoveError: LocalizedError {
        case noCutFiles, invalidDestination, nameConflict, sourceMissing(String)
        case batchFailed(reason: String, restored: [String], unresolved: [String], pending: [String])
        var errorDescription: String? {
            switch self {
            case .noCutFiles: return "剪贴板中没有待移动的文件。"
            case .invalidDestination: return "目标文件夹不可用。"
            case .nameConflict: return "目标位置已有同名文件，未执行移动。"
            case .sourceMissing(let name): return "原文件 \(name) 已不存在，未执行移动。"
            case let .batchFailed(reason, restored, unresolved, pending):
                var sections = ["批量移动未完成：\(reason)"]
                if !restored.isEmpty { sections.append("已恢复到原位置：\n" + restored.joined(separator: "\n")) }
                if !unresolved.isEmpty { sections.append("未能恢复，请检查以下位置：\n" + unresolved.joined(separator: "\n\n")) }
                if !pending.isEmpty { sections.append("未完成移动，请检查原位置：\n" + pending.joined(separator: "\n")) }
                return sections.joined(separator: "\n\n")
            }
        }
    }
}
