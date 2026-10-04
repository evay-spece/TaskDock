import AppKit

@main
@MainActor
struct TrashStatusSelfTest {
    static func main() throws {
        let fileManager = FileManager.default
        let trash = fileManager.temporaryDirectory
            .appendingPathComponent("taskdock-trash-test-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: trash) }

        precondition(!TrashStatusService.hasItems(in: trash), "Empty trash detected as full")
        try Data().write(to: trash.appendingPathComponent(".DS_Store"))
        precondition(!TrashStatusService.hasItems(in: trash), "Metadata detected as a user item")

        let file = trash.appendingPathComponent("document.txt")
        try Data().write(to: file)
        precondition(TrashStatusService.hasItems(in: trash), "File did not make trash full")
        try fileManager.removeItem(at: file)

        let folder = trash.appendingPathComponent("Folder", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        precondition(TrashStatusService.hasItems(in: trash), "Folder did not make trash full")
        try fileManager.removeItem(at: folder)
        precondition(!TrashStatusService.hasItems(in: trash), "Empty trash did not reset")
        print("TRASH_STATUS_EMPTY_FULL_TRANSITIONS_OK")
        if let finderStatus = TrashStatusService.finderTrashIsFull() {
            print("FINDER_TRASH_STATUS_\(finderStatus ? "FULL" : "EMPTY")")
        } else {
            print("FINDER_TRASH_STATUS_UNAVAILABLE")
        }
    }
}
