import Foundation

@main struct BrowserBridgeSelfTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TaskDockBrowserProtocolTest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func object(profile: String = "11111111-1111-4111-8111-111111111111", browser: String = "chrome", received: Int64 = 25, total: Int64 = 100, active: Int = 1) -> [String: Any] {
            ["version": 1, "type": "snapshot", "browser": browser, "profile": profile, "receivedBytes": received, "totalBytes": total, "activeCount": active, "unknownCount": 0]
        }
        func parse(_ object: [String: Any]) throws -> BrowserProgressSnapshot {
            try BrowserProgressSnapshot.parse(JSONSerialization.data(withJSONObject: object))
        }
        let now = Date()
        let first = try parse(object())
        let second = try parse(object(profile: "22222222-2222-4222-8222-222222222222", received: 75, total: 300))
        let store = BrowserProgressStore(directory: root.appendingPathComponent("state"))
        let session = UUID()
        try store.save(first, session: session, now: now)
        try store.save(second, session: session, now: now)
        precondition(store.fraction(browser: .chrome, now: now) == 0.25)
        precondition(store.fraction(browser: .edge, now: now) == nil)
        precondition(store.fraction(browser: .chrome, now: now.addingTimeInterval(16)) == nil)
        precondition(store.fraction(browser: .chrome, now: now.addingTimeInterval(-3)) == nil)
        store.clear(first, session: UUID())
        precondition(store.fraction(browser: .chrome, now: now) == 0.25) // a previous connection cannot clear a newer one
        store.clear(first, session: session)
        store.clear(second, session: session)
        precondition(store.fraction(browser: .chrome, now: now) == nil)
        let ended = try parse(object(received: 0, total: 0, active: 0))
        try store.save(ended, session: session, now: now)
        precondition(store.fraction(browser: .chrome, now: now) == nil)
        var invalids = [[String: Any]]()
        invalids += [object(profile: "../../escape"), object(browser: "firefox"), object(browser: "safari"), object(received: -1), object(received: 101), object(received: 0, total: 100, active: 0)]
        var extra = object(); extra["url"] = "https://private.example"; invalids.append(extra)
        var version = object(); version["version"] = 2; invalids.append(version)
        var bool = object(); bool["receivedBytes"] = true; invalids.append(bool)
        for invalid in invalids { precondition((try? parse(invalid)) == nil) }
        let executable = URL(fileURLWithPath: "/usr/bin/true")
        let home = root.appendingPathComponent("home")
        for browser in ProgressBrowser.bridgeBrowsers {
            let path = try BrowserBridgeRegistration.register(browser: browser, executable: executable, home: home)
            let data = try Data(contentsOf: path)
            let manifest = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            precondition(manifest["allowed_origins"] as? [String] == [BrowserBridgeIdentity.origin])
            precondition(manifest["path"] as? String == executable.path)
            try BrowserBridgeRegistration.register(browser: browser, executable: executable, home: home)
            let files = try FileManager.default.contentsOfDirectory(atPath: path.deletingLastPathComponent().path)
            precondition(files.count == 2)
            do { try BrowserBridgeRegistration.unregister(browser: browser, executable: URL(fileURLWithPath: "/usr/bin/false"), home: home); preconditionFailure("must reject mismatched registration") } catch {}
            try BrowserBridgeRegistration.unregister(browser: browser, executable: executable, home: home)
            precondition(!FileManager.default.fileExists(atPath: path.path))
        }
        var individual = object()
        individual["version"] = 2
        individual["downloads"] = [
            ["id": 1, "filename": "同名文件.zip", "receivedBytes": 25, "totalBytes": 100, "paused": false],
            ["id": 2, "filename": "同名文件.zip", "receivedBytes": 75, "totalBytes": 100, "paused": true],
            ["id": 3, "filename": "未知大小.dat", "receivedBytes": 50, "totalBytes": 0, "paused": false]
        ]
        let perFile = try parse(individual)
        try store.save(perFile, session: session, now: now)
        let tasks = store.tasks(now: now)
        precondition(tasks.count == 3 && Set(tasks.map(\.id)).count == 3)
        precondition(tasks[0].progress == 0.25 && tasks[1].download.paused && tasks[2].progress == nil)
        precondition(store.tasks(now: now.addingTimeInterval(16)).isEmpty)
        var otherProfile = individual
        otherProfile["profile"] = "22222222-2222-4222-8222-222222222222"
        try store.save(parse(otherProfile), session: session, now: now)
        precondition(Set(store.tasks(now: now).map(\.id)).count == 6)
        for badName in ["/private/report.zip", "C:\\Users\\report.zip", "bad\nname.zip"] {
            var invalid = individual
            invalid["downloads"] = [["id": 1, "filename": badName, "receivedBytes": 25, "totalBytes": 100, "paused": false]]
            precondition((try? parse(invalid)) == nil)
        }
        // Completed paths persist after TTL and native disconnect, with v1/v2 compatibility.
        let completedFile = root.appendingPathComponent("已完成.txt")
        try Data("test".utf8).write(to: completedFile)
        var completed = object(received: 0, total: 0, active: 0)
        completed["version"] = 3
        completed["downloads"] = [["id": 9, "filename": "已完成.txt", "receivedBytes": 4, "totalBytes": 4,
            "paused": false, "complete": true, "localPath": completedFile.path]]
        let finished = try parse(completed)
        try store.save(finished, session: session, now: now)
        precondition(store.tasks(now: now.addingTimeInterval(60)).count == 1)
        precondition(store.tasks(now: now.addingTimeInterval(60))[0].status == "已完成")
        store.clear(finished, session: session)
        precondition(store.tasks(now: Date().addingTimeInterval(60)).count == 1)
        let freshStore = BrowserProgressStore(directory: store.directory)
        precondition(freshStore.tasks(now: now.addingTimeInterval(1799)).count == 1)
        // Receiving the same completed item again must not reset the 30-minute clock.
        try freshStore.save(finished, session: UUID(), now: now.addingTimeInterval(1799))
        precondition(freshStore.tasks(now: now.addingTimeInterval(1799)).count == 1)
        precondition(freshStore.tasks(now: now.addingTimeInterval(1800)).isEmpty)
        precondition(freshStore.tasks(now: now.addingTimeInterval(3600)).isEmpty)
        var dated = completed
        var datedRecords = dated["downloads"] as! [[String: Any]]
        datedRecords[0]["completedAt"] = now.addingTimeInterval(-3600).timeIntervalSince1970
        dated["downloads"] = datedRecords
        try freshStore.save(parse(dated), session: UUID(), now: now)
        precondition(freshStore.tasks(now: now.addingTimeInterval(60)).isEmpty)
        for path in ["relative/已完成.txt", "https://example.com/已完成.txt", "/tmp/other.txt", "/tmp/bad\n/已完成.txt"] {
            var bad = completed
            bad["downloads"] = [["id": 9, "filename": "已完成.txt", "receivedBytes": 4, "totalBytes": 4,
                "paused": false, "complete": true, "localPath": path]]
            precondition((try? parse(bad)) == nil)
        }
        try FileManager.default.removeItem(at: completedFile)
        precondition(store.tasks(now: now.addingTimeInterval(60)).isEmpty)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.directory.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o700)
        print("BROWSER_BRIDGE_OK individual-files same-name profiles paused unknown-size basename-only ttl v1-compatible registration")
    }
}
