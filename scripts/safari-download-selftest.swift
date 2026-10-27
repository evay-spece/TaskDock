import Foundation

@main struct SafariDownloadSelfTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskDockSafariDownloadTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let plistURL = root.appendingPathComponent("Downloads.plist")
        let package = root.appendingPathComponent("example.bin.download")
        let partial = package.appendingPathComponent("example.bin")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 40).write(to: partial)
        let now = Date()
        var entry: [String: Any] = [
            "DownloadEntryIdentifier": "11111111-1111-4111-8111-111111111111",
            "DownloadEntryDateAddedKey": now.addingTimeInterval(-30),
            "DownloadEntryPath": partial.path,
            "DownloadEntryProgressBytesSoFar": 35,
            "DownloadEntryProgressTotalToLoad": 100
        ]
        func save(_ entries: [[String: Any]]) throws {
            let data = try PropertyListSerialization.data(
                fromPropertyList: ["DownloadHistory": entries], format: .binary, options: 0)
            try data.write(to: plistURL, options: .atomic)
        }
        let store = SafariDownloadStore(plistURL: plistURL)
        try save([entry])
        let active = store.tasks(now: now)
        precondition(active.count == 1 && active[0].browser == .safari)
        precondition(active[0].download.filename == "example.bin")
        precondition(active[0].progress == 0.4 && !active[0].download.isComplete)
        precondition(active[0].download.localPath == nil)
        let id = active[0].id
        var second = entry
        second["DownloadEntryIdentifier"] = "22222222-2222-4222-8222-222222222222"
        try save([entry, second])
        let concurrent = store.tasks(now: now)
        precondition(concurrent.count == 2 && Set(concurrent.map(\.id)).count == 2)
        var oldCancelled = entry
        oldCancelled["DownloadEntryDateAddedKey"] = now.addingTimeInterval(-86_400)
        oldCancelled["DownloadEntryErrorCodeDictionaryKey"] = -999
        try save(Array(repeating: oldCancelled, count: 130) + [entry])
        precondition(store.tasks(now: now).count == 1)

        entry["DownloadEntryProgressTotalToLoad"] = 0
        try save([entry])
        precondition(store.tasks(now: now)[0].progress == nil)
        entry["DownloadEntryProgressTotalToLoad"] = 100
        entry["DownloadEntryIsPausedKey"] = true
        try save([entry])
        precondition(store.tasks(now: now)[0].download.paused)
        entry.removeValue(forKey: "DownloadEntryIsPausedKey")

        let final = root.appendingPathComponent("example.bin")
        try Data(repeating: 0, count: 100).write(to: final)
        entry["DownloadEntryDateFinishedKey"] = now
        try save([entry])
        let completed = store.tasks(now: now)
        precondition(completed.count == 1 && completed[0].id == id)
        precondition(completed[0].download.isComplete && completed[0].download.fileURL == final)
        precondition(store.tasks(now: now.addingTimeInterval(1800)).isEmpty)

        entry.removeValue(forKey: "DownloadEntryDateFinishedKey")
        entry["DownloadEntryErrorCodeDictionaryKey"] = -999
        try save([entry])
        precondition(store.tasks(now: now).isEmpty)
        entry.removeValue(forKey: "DownloadEntryErrorCodeDictionaryKey")
        try FileManager.default.removeItem(at: package)
        try save([entry])
        precondition(store.tasks(now: now).isEmpty)
        print("SAFARI_DOWNLOAD_OK active unknown-size paused completed cancelled missing ttl stable-id")
    }
}
