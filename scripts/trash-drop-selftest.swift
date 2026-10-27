import AppKit

@main
struct TrashDropSelfTest {
    static func main() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("taskdock-trash-test-\(UUID().uuidString)")
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: folder) }
        let target = folder.appendingPathComponent("target.txt")
        let link = folder.appendingPathComponent("link.txt")
        try "TaskDock test only".write(to: target, atomically: true, encoding: .utf8)
        try manager.createSymbolicLink(at: link, withDestinationURL: target)
        let links = try TrashActions.moveToTrash([link])
        precondition(links.count == 1 && manager.fileExists(atPath: target.path))
        precondition(!manager.fileExists(atPath: link.path))
        try manager.moveItem(at: links[0], to: link)
        let files = try TrashActions.moveToTrash([target])
        precondition(files.count == 1 && !manager.fileExists(atPath: target.path))
        try manager.moveItem(at: files[0], to: target)
        let restored = try String(contentsOf: target, encoding: .utf8)
        precondition(restored == "TaskDock test only")
        print("TRASH_DROP_OK file-recoverable symlink-target-preserved own-fixtures-cleaned")
    }
}
