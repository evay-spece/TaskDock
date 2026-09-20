import AppKit
import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    enum Status {
        case idle
        case checking
        case upToDate(String)
        case updateAvailable(version: String, url: URL)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    let currentVersion: String
    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/evay-spece/TaskDock/releases/latest")!

    init(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") {
        self.currentVersion = currentVersion
    }

    func check() {
        guard case .checking = status else {
            status = .checking
            Task { await fetchLatestRelease() }
            return
        }
    }

    func openRelease(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = versionParts(candidate)
        let currentParts = versionParts(current)
        let count = max(candidateParts.count, currentParts.count)
        for index in 0..<count {
            let lhs = index < candidateParts.count ? candidateParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
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
            if Self.isNewer(release.tagName, than: currentVersion) {
                status = .updateAvailable(version: normalizedVersion(release.tagName), url: releaseURL)
            } else {
                status = .upToDate(normalizedVersion(release.tagName))
            }
        } catch {
            status = .failed("检查失败，请稍后重试")
        }
    }

    private static func versionParts(_ version: String) -> [Int] {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                Int(component.prefix { $0.isNumber }) ?? 0
            }
    }

    private func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private enum UpdateError: Error {
    case invalidResponse
}
