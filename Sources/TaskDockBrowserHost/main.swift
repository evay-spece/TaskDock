import Foundation
import TaskDockBrowserProtocol
import Darwin

// Native Messaging stdout is framed JSON only. Never print diagnostics here.
func readExactly(_ count: Int) throws -> Data? {
    var result = Data()
    while result.count < count {
        let chunk = try FileHandle.standardInput.read(upToCount: count - result.count) ?? Data()
        if chunk.isEmpty {
            if result.isEmpty { return nil }
            throw BrowserBridgeError.invalidMessage
        }
        result.append(chunk)
    }
    return result
}
func reply(_ ok: Bool) throws {
    let payload = try JSONSerialization.data(withJSONObject: ["ok": ok, "version": 1])
    var length = UInt32(payload.count).littleEndian
    try FileHandle.standardOutput.write(contentsOf: withUnsafeBytes(of: &length) { Data($0) })
    try FileHandle.standardOutput.write(contentsOf: payload)
}
let arguments = Array(CommandLine.arguments.dropFirst())
let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
if arguments.count == 2, ["--install", "--uninstall"].contains(arguments[0]), let browser = ProgressBrowser(rawValue: arguments[1]) {
    do {
        if arguments[0] == "--install" { try BrowserBridgeRegistration.register(browser: browser, executable: executable) }
        else { try BrowserBridgeRegistration.unregister(browser: browser, executable: executable) }
        FileHandle.standardError.write(Data("\(browser.label) 本机通信配置已更新。\n".utf8))
        exit(0)
    } catch { FileHandle.standardError.write(Data("未能更新本机通信配置：\(error.localizedDescription)\n".utf8)); exit(1) }
}
guard arguments.first == BrowserBridgeIdentity.origin else { exit(2) }
let testDirectory = ProcessInfo.processInfo.environment["TASKDOCK_BROWSER_BRIDGE_STATE_DIR"].map { URL(fileURLWithPath: $0) }
let store = testDirectory.map { BrowserProgressStore(directory: $0) } ?? BrowserProgressStore()
let session = UUID()
var bound: BrowserProgressSnapshot?
defer { if let bound { store.clear(bound, session: session) } }
do {
    while let header = try readExactly(4) {
        let bytes = Array(header)
        let count = Int(UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24)
        guard count > 0, count <= 262144, let data = try readExactly(count) else { throw BrowserBridgeError.invalidMessage }
        let snapshot = try BrowserProgressSnapshot.parse(data)
        if let bound, bound.browser != snapshot.browser || bound.profile != snapshot.profile { throw BrowserBridgeError.invalidMessage }
        try store.save(snapshot, session: session)
        bound = snapshot
        try reply(true)
    }
} catch {
    try? reply(false)
}
