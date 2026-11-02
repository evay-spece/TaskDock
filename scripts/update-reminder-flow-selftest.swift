import Foundation

private final class StubReleaseProtocol: URLProtocol {
    static var notes: String?
    static var releaseVersion = "1.8.0"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let version = Self.releaseVersion
        let bodyField = Self.notes.map { ",\"body\":\"\($0)\"" } ?? ""
        let json = """
        {"tag_name":"v\(version)","html_url":"https://example.test/releases/\(version)",
         "assets":[{"name":"TaskDock-\(version)-macOS-arm64.zip",
         "browser_download_url":"https://example.test/TaskDock-\(version)-macOS-arm64.zip",
         "digest":"sha256:\(String(repeating: "0", count: 64))"}]\(bodyField)}
        """
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
@MainActor
struct UpdateReminderFlowSelfTest {
    static func main() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubReleaseProtocol.self]
        let session = URLSession(configuration: config)
        let endpoint = URL(string: "https://example.test/latest")!

        for (candidate, automatic, expectedCount) in [
            ("1.8.0", true, 1),
            ("2.0.0", true, 1),
            ("1.7.2", true, 0),
            ("1.8.0", false, 0)
        ] {
            StubReleaseProtocol.notes = automatic ? "更新说明" : nil
            StubReleaseProtocol.releaseVersion = candidate
            let checker = UpdateChecker(currentVersion: "1.7.1",
                                        latestReleaseAPI: endpoint, session: session)
            var reminders = 0
            checker.onAutomaticMajorMinorUpdateAvailable = { _ in reminders += 1 }
            checker.check(automatic: automatic)
            for _ in 0..<100 {
                if case .updateAvailable = checker.status { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            guard case .updateAvailable(let update) = checker.status else {
                preconditionFailure("Missing update for \(candidate)")
            }
            precondition(update.version == candidate && reminders == expectedCount)
            precondition(update.releaseNotes == (StubReleaseProtocol.notes ?? ""))
        }
        print("UPDATE_REMINDER_FLOW_OK")
    }
}
