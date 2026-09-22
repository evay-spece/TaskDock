import Foundation

@main
@MainActor
struct UpdateCheckerSelfTest {
    static func main() async {
        let checker = UpdateChecker(currentVersion: "0.1.0")
        checker.check()

        for _ in 0..<100 {
            switch checker.status {
            case .updateAvailable(let update):
                precondition(UpdateSupport.isNewer(update.version, than: "0.1.0"))
                precondition(update.assetURL.lastPathComponent == "TaskDock-\(update.version)-macOS-arm64.zip")
                precondition(update.digest.lowercased().hasPrefix("sha256:"))
                print("UPDATE_CHECK_OK version=\(update.version) asset=\(update.assetURL.lastPathComponent)")
                return
            case .failed(let message, _):
                preconditionFailure(message)
            default:
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        preconditionFailure("update check timed out")
    }
}
