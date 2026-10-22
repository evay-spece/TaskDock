import Foundation

public struct BrowserDownloadRecord: Codable, Equatable {
    public let id: Int64
    public let filename: String
    public let receivedBytes: Int64
    public let totalBytes: Int64
    public let paused: Bool
    public let complete: Bool?
    public let localPath: String?
    /// Unix seconds recorded on first receipt of completion, preserved across snapshots.
    public let completedAt: Double?
    public var isComplete: Bool { complete == true }
    public var fileURL: URL? {
        guard isComplete, let localPath, localPath.hasPrefix("/"), localPath.utf8.count <= 8192,
              !localPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              URL(fileURLWithPath: localPath).lastPathComponent == filename else { return nil }
        return URL(fileURLWithPath: localPath)
    }

    public var isValid: Bool {
        (completedAt == nil || (completedAt!.isFinite && completedAt! > 0)) &&
        (isComplete ? (fileURL != nil && !paused) : localPath == nil) &&
        id >= 0 && id <= 9_007_199_254_740_991 && !filename.isEmpty && filename.count <= 255 &&
        !filename.contains("/") && !filename.contains("\\") &&
        !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) }) &&
        receivedBytes >= 0 && receivedBytes <= 9_007_199_254_740_991 && totalBytes >= 0 && totalBytes <= 9_007_199_254_740_991 &&
        (totalBytes == 0 || receivedBytes <= totalBytes)
    }
}

public struct BrowserDownloadTask: Identifiable, Equatable {
    public let browser: ProgressBrowser
    public let profile: String
    public let download: BrowserDownloadRecord
    public var id: String { "\(browser.rawValue)-\(profile)-\(download.id)" }
    public var progress: Double? {
        guard !download.isComplete, download.totalBytes > 0 else { return nil }
        return min(0.999, max(0.001, Double(download.receivedBytes) / Double(download.totalBytes)))
    }
    public var status: String {
        if download.isComplete { return "已完成" }
        if download.paused { return "已暂停" }
        if let progress { return "\(Int(progress * 100))%" }
        return "正在下载，大小未知"
    }
}
