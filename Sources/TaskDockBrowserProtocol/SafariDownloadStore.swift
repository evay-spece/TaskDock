import Foundation

/// Reads Safari's local download history without a browser extension.
public struct SafariDownloadStore {
    public let plistURL: URL

    public init(plistURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Safari/Downloads.plist")) {
        self.plistURL = plistURL
    }

    public func tasks(now: Date = Date()) -> [BrowserDownloadTask] {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let entries = (plist as? [String: Any])?["DownloadHistory"] as? [[String: Any]] else {
            return []
        }
        return entries.sorted {
            ($0["DownloadEntryDateAddedKey"] as? Date ?? .distantPast)
                > ($1["DownloadEntryDateAddedKey"] as? Date ?? .distantPast)
        }.prefix(128).compactMap { entry -> (Date, BrowserDownloadTask)? in
            guard let added = entry["DownloadEntryDateAddedKey"] as? Date,
                  added <= now.addingTimeInterval(2),
                  entry["DownloadEntryErrorCodeDictionaryKey"] == nil,
                  let identifier = entry["DownloadEntryIdentifier"] as? String,
                  !identifier.isEmpty, identifier.utf8.count <= 128,
                  let path = entry["DownloadEntryPath"] as? String,
                  path.hasPrefix("/"), path.utf8.count <= 8192 else { return nil }

            let destination = URL(fileURLWithPath: path)
            let package = destination.deletingLastPathComponent()
            let inDownloadPackage = package.pathExtension == "download"
            let finished = entry["DownloadEntryDateFinishedKey"] as? Date
            let total = max(0, (entry["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value ?? 0)
            let recorded = max(0, (entry["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0)
            let fileManager = FileManager.default
            let filename: String
            let received: Int64
            let localPath: String?

            if let finished {
                guard finished <= now.addingTimeInterval(2),
                      now.timeIntervalSince(finished) < 30 * 60 else { return nil }
                let finalURL = inDownloadPackage
                    ? package.deletingPathExtension() : destination
                guard let values = try? finalURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true else { return nil }
                filename = finalURL.lastPathComponent
                received = max(0, Int64(values.fileSize ?? 0))
                localPath = finalURL.path
            } else {
                let activePath = inDownloadPackage ? package.path : destination.path
                guard fileManager.fileExists(atPath: activePath) else { return nil }
                filename = destination.lastPathComponent
                let onDisk = (try? fileManager.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
                received = max(onDisk, recorded)
                localPath = nil
            }

            let boundedTotal = min(total, 9_007_199_254_740_991)
            let boundedReceived = min(received, boundedTotal > 0 ? boundedTotal : 9_007_199_254_740_991)
            let record = BrowserDownloadRecord(
                id: Self.stableID(identifier), filename: filename,
                receivedBytes: boundedReceived, totalBytes: boundedTotal,
                paused: finished == nil && (entry["DownloadEntryIsPausedKey"] as? Bool ?? false),
                complete: finished != nil, localPath: localPath,
                completedAt: finished?.timeIntervalSince1970
            )
            guard record.isValid else { return nil }
            return (added, BrowserDownloadTask(browser: .safari, profile: "safari", download: record))
        }
        .sorted { $0.0 > $1.0 }
        .map(\.1)
    }

    private static func stableID(_ identifier: String) -> Int64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in identifier.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Int64(hash & 0x001F_FFFF_FFFF_FFFF)
    }
}
