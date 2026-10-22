import Foundation
import TaskDockBrowserProtocol

/// Safari downloads are owned by the application, not by an AX window. Read its
/// local download state and attach it to one of Safari's taskbar windows.
enum BrowserDownloadProgress {
    static func read(bundleIdentifier: String?) -> Double? {
        guard bundleIdentifier == "com.apple.Safari" else { return nil }
        return safari()
    }

    private static func safari() -> Double? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Downloads.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let entries = (plist as? [String: Any])?["DownloadHistory"] as? [[String: Any]] else {
            return nil
        }
        var received: Int64 = 0
        var total: Int64 = 0
        let cutoff = Date().addingTimeInterval(-4 * 60 * 60)
        for entry in entries {
            guard entry["DownloadEntryDateFinishedKey"] == nil,
                  let added = entry["DownloadEntryDateAddedKey"] as? Date, added > cutoff,
                  let path = entry["DownloadEntryPath"] as? String,
                  let expected = (entry["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value,
                  expected > 0 else { continue }
            let destination = URL(fileURLWithPath: path)
            let package = destination.deletingLastPathComponent()
            guard package.pathExtension == "download",
                  FileManager.default.fileExists(atPath: destination.path) else { continue }
            let onDisk = fileSize(at: destination) ?? 0
            let recorded = (entry["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
            received += min(expected, max(onDisk, recorded))
            total += expected
        }
        return fraction(received: received, total: total)
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    private static func fraction(received: Int64, total: Int64) -> Double? {
        guard total > 0 else { return nil }
        return min(0.999, max(0.001, Double(received) / Double(total)))
    }
}
