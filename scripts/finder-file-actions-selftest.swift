import AppKit

@main
struct FinderFileActionsSelfTest {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("TaskDock-file-actions-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { original -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer {
            pasteboard.clearContents()
            if !savedItems.isEmpty { pasteboard.writeObjects(savedItems) }
        }

        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)

        let custom = FileTypeEntry(id: UUID().uuidString, title: "测试文件", baseName: "测试文件",
                                   fileExtension: "qa", enabled: true)
        let first = try FileCreator.create(custom, in: source)
        try Data("keep-original".utf8).write(to: first)
        let second = try FileCreator.create(custom, in: source)
        precondition(first != second)
        let originalContents = try Data(contentsOf: first)
        precondition(originalContents == Data("keep-original".utf8))
        precondition(second.lastPathComponent == "测试文件 2.qa")

        // A normal copy must never be treated as a pending cut.
        let plainCopy = NSPasteboardItem()
        plainCopy.setString(first.absoluteString, forType: .fileURL)
        pasteboard.clearContents()
        pasteboard.writeObjects([plainCopy])
        precondition(ClipboardCutter.cutFiles().isEmpty)

        precondition(ClipboardCutter.cut([first, second]))
        let targets = try ClipboardCutter.move(to: destination)
        precondition(targets.count == 2)
        precondition(!manager.fileExists(atPath: first.path))
        precondition(!manager.fileExists(atPath: second.path))
        let movedContents = try Data(contentsOf: targets[0])
        precondition(movedContents == Data("keep-original".utf8))
        precondition(ClipboardCutter.cutFiles().isEmpty)

        // One collision must prevent the entire batch from being moved.
        let a = source.appendingPathComponent("a.txt")
        let b = source.appendingPathComponent("b.txt")
        let collision = destination.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)
        try Data("existing".utf8).write(to: collision)
        precondition(ClipboardCutter.cut([a, b]))
        do {
            _ = try ClipboardCutter.move(to: destination)
            preconditionFailure("Collision should stop the batch")
        } catch ClipboardCutter.MoveError.nameConflict { }
        precondition(manager.fileExists(atPath: a.path))
        precondition(manager.fileExists(atPath: b.path))
        precondition(!manager.fileExists(atPath: destination.appendingPathComponent("a.txt").path))
        let collisionContents = try Data(contentsOf: collision)
        precondition(collisionContents == Data("existing".utf8))
        print("FINDER_FILE_ACTIONS_OK create_no_overwrite normal_copy_ignored move_source_removed collision_batch_preserved")
    }
}
