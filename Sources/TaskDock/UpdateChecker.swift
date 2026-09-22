import AppKit
import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    struct AvailableUpdate {
        let version: String
        let releaseURL: URL
        let assetURL: URL
        let digest: String
    }

    enum Status {
        case idle
        case checking
        case upToDate(String)
        case updateAvailable(AvailableUpdate)
        case downloading(String)
        case verifying(String)
        case installing(String)
        case failed(message: String, releaseURL: URL?)
    }

    @Published private(set) var status: Status = .idle

    let currentVersion: String
    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/evay-spece/TaskDock/releases/latest")!

    init(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") {
        self.currentVersion = currentVersion
    }

    func check() {
        guard !isBusy else { return }
        status = .checking
        Task { await fetchLatestRelease() }
    }

    func downloadAndRestart(_ update: AvailableUpdate) {
        guard !isBusy else { return }
        Task { await performUpdate(update) }
    }

    func openRelease(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        UpdateSupport.isNewer(candidate, than: current)
    }

    private var isBusy: Bool {
        switch status {
        case .checking, .downloading, .verifying, .installing:
            return true
        default:
            return false
        }
    }

    private func fetchLatestRelease() async {
        do {
            var request = URLRequest(url: latestReleaseAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("TaskDock/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw UpdateError.invalidResponse
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let releaseURL = URL(string: release.htmlURL) else { throw UpdateError.invalidResponse }
            let version = UpdateSupport.normalizedVersion(release.tagName)
            guard Self.isNewer(version, than: currentVersion) else {
                status = .upToDate(currentVersion)
                return
            }

            let expectedAssetName = "TaskDock-\(version)-macOS-arm64.zip"
            guard let asset = release.assets.first(where: { $0.name == expectedAssetName }),
                  let assetURL = URL(string: asset.downloadURL),
                  let digest = asset.digest,
                  digest.lowercased().hasPrefix("sha256:") else {
                status = .failed(message: "新版本缺少可验证的安装包", releaseURL: releaseURL)
                return
            }
            status = .updateAvailable(AvailableUpdate(
                version: version,
                releaseURL: releaseURL,
                assetURL: assetURL,
                digest: digest
            ))
        } catch {
            status = .failed(message: "检查失败，请稍后重试", releaseURL: nil)
        }
    }

    private func performUpdate(_ update: AvailableUpdate) async {
        var stagingRoot: URL?
        do {
            status = .downloading(update.version)
            var request = URLRequest(url: update.assetURL)
            request.setValue("TaskDock/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (temporaryArchive, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw UpdateError.invalidResponse
            }

            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("TaskDockUpdate-\(UUID().uuidString)", isDirectory: true)
            stagingRoot = root
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let archive = root.appendingPathComponent("TaskDock-\(update.version)-macOS-arm64.zip")
            try FileManager.default.moveItem(at: temporaryArchive, to: archive)

            status = .verifying(update.version)
            let currentAppURL = Bundle.main.bundleURL
            let prepared = try await Task.detached(priority: .userInitiated) {
                try UpdateSupport.prepareCandidate(
                    archiveURL: archive,
                    stagingRoot: root,
                    expectedVersion: update.version,
                    expectedDigest: update.digest,
                    currentAppURL: currentAppURL
                )
            }.value

            status = .installing(update.version)
            try UpdateSupport.launchInstaller(
                prepared: prepared,
                currentAppURL: currentAppURL,
                currentProcessID: ProcessInfo.processInfo.processIdentifier
            )
            NSApp.terminate(nil)
        } catch {
            if let stagingRoot {
                try? FileManager.default.removeItem(at: stagingRoot)
            }
            let message = (error as? LocalizedError)?.errorDescription ?? "更新失败，请稍后重试"
            status = .failed(message: message, releaseURL: update.releaseURL)
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let downloadURL: String
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case digest
    }
}

private enum UpdateError: Error {
    case invalidResponse
}
