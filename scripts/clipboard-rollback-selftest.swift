import AppKit

@main
struct ClipboardRollbackSelfTest {
    enum Failure: Error { case injected }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let files = ["a.txt", "b.txt", "c.txt"].map { source.appendingPathComponent($0) }
        let targets = files.map { destination.appendingPathComponent($0.lastPathComponent) }
        for file in files { try Data(file.lastPathComponent.utf8).write(to: file) }
        var call = 0
        do {
            try ClipboardCutter.executeMoves(files: files, targets: targets) { from, to in
                call += 1
                if call == 3 || call == 4 { throw Failure.injected }
                try FileManager.default.moveItem(at: from, to: to)
            }
            preconditionFailure("Expected partial rollback failure")
        } catch ClipboardCutter.MoveError.batchFailed(_, let restored, let unresolved, let pending) {
            precondition(restored == [files[0].path])
            precondition(unresolved.count == 1 && unresolved[0].contains(targets[1].path))
            precondition(pending == [files[2].path])
            precondition(FileManager.default.fileExists(atPath: files[0].path))
            precondition(FileManager.default.fileExists(atPath: targets[1].path))
            precondition(FileManager.default.fileExists(atPath: files[2].path))
            let retainedData = try Data(contentsOf: targets[1])
            precondition(retainedData == Data("b.txt".utf8))
        }
        try FileManager.default.moveItem(at: targets[1], to: files[1])
        call = 0
        do {
            try ClipboardCutter.executeMoves(files: files, targets: targets) { from, to in
                call += 1
                if call == 3 { throw Failure.injected }
                try FileManager.default.moveItem(at: from, to: to)
            }
            preconditionFailure("Expected restored failure")
        } catch ClipboardCutter.MoveError.batchFailed(_, let restored, let unresolved, _) {
            precondition(restored.count == 2 && unresolved.isEmpty)
        }
        try ClipboardCutter.executeMoves(files: files, targets: targets)
        precondition(targets.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        print("CLIPBOARD_ROLLBACK_OK partial_restore full_restore success")
    }
}
