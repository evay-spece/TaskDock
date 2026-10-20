import Foundation

@main
struct UpdateSupportSelfTest {
    static func main() throws {
        precondition(UpdateSupport.isNewer("v0.2.3", than: "0.2.2"))
        precondition(UpdateSupport.isNewer("1.0.0", than: "0.9.9"))
        precondition(!UpdateSupport.isNewer("0.2.2", than: "0.2.2"))
        precondition(!UpdateSupport.isNewer("0.2.1", than: "0.2.2"))

        guard CommandLine.arguments.count == 5 else {
            print("usage: update-support-selftest ARCHIVE VERSION EXPECTED_DIGEST CURRENT_APP")
            return
        }
        let archive = URL(fileURLWithPath: CommandLine.arguments[1])
        let expectedVersion = CommandLine.arguments[2]
        let digest = CommandLine.arguments[3]
        let currentApp = URL(fileURLWithPath: CommandLine.arguments[4])
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskDockUpdateSelfTest-\(UUID().uuidString)", isDirectory: true)
        let stagingRoot = testRoot.appendingPathComponent("stage", isDirectory: true)
        let targetDirectory = testRoot.appendingPathComponent("target", isDirectory: true)
        let targetApp = targetDirectory.appendingPathComponent("TaskDock.app", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let copy = Process()
        copy.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        copy.arguments = [currentApp.path, targetApp.path]
        try copy.run()
        copy.waitUntilExit()
        precondition(copy.terminationStatus == 0)

        let prepared = try UpdateSupport.prepareCandidate(
            archiveURL: archive,
            stagingRoot: stagingRoot,
            expectedVersion: expectedVersion,
            expectedDigest: digest,
            currentAppURL: targetApp
        )

        let oldProcess = Process()
        oldProcess.executableURL = URL(fileURLWithPath: "/bin/sleep")
        oldProcess.arguments = ["5"]
        try oldProcess.run()
        try UpdateSupport.launchInstaller(
            prepared: prepared,
            currentAppURL: targetApp,
            currentProcessID: oldProcess.processIdentifier,
            relaunch: false,
            backupDirectory: testRoot.appendingPathComponent("backups", isDirectory: true)
        )
        oldProcess.terminate()
        oldProcess.waitUntilExit()

        let deadline = Date().addingTimeInterval(5)
        var installedVersion: String?
        repeat {
            Thread.sleep(forTimeInterval: 0.05)
            installedVersion = Bundle(url: targetApp)?
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        } while installedVersion != expectedVersion && Date() < deadline
        precondition(installedVersion == expectedVersion)
        let backupDirectory = testRoot.appendingPathComponent("backups", isDirectory: true)
        let archiveDeadline = Date().addingTimeInterval(5)
        var backups: [URL] = []
        repeat {
            backups = try FileManager.default.contentsOfDirectory(
                at: backupDirectory, includingPropertiesForKeys: nil
            )
            if backups.count == 1, backups[0].pathExtension == "zip" { break }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < archiveDeadline
        precondition(backups.count == 1 && backups[0].pathExtension == "zip")
        try verifyArchive(backups[0])

        let legacyApp = backupDirectory.appendingPathComponent("TaskDock-before-online-update-legacy.app")
        let legacyArchive = legacyApp.appendingPathExtension("zip")
        try FileManager.default.copyItem(at: currentApp, to: legacyApp)
        UpdateSupport.archiveLegacyBackups(in: backupDirectory)
        precondition(!FileManager.default.fileExists(atPath: legacyApp.path))
        precondition(FileManager.default.fileExists(atPath: legacyArchive.path))
        try verifyArchive(legacyArchive)
        print("UPDATE_SUPPORT_OK")
    }

    private static func verifyArchive(_ archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-tq", archive.path]
        try process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
    }
}
