import Foundation

/// A continuous dwell outside the shelf is required; returning resets it.
struct FavoriteDragRemovalState {
    static let delay: TimeInterval = 0.5
    private(set) var outsideSince: TimeInterval?

    mutating func update(isOutside: Bool, now: TimeInterval) {
        if !isOutside { outsideSince = nil }
        else if outsideSince == nil { outsideSince = now }
    }

    func isReady(now: TimeInterval) -> Bool {
        guard let outsideSince else { return false }
        return now - outsideSince >= Self.delay
    }

    func shouldRemove(onReleaseOutside: Bool, now: TimeInterval) -> Bool {
        onReleaseOutside && isReady(now: now)
    }

    mutating func cancel() { outsideSince = nil }
}

struct FavoriteShelfInsertion: Equatable {
    let appIndex: Int
    let folderIndex: Int
    let appCount: Int
    let folderCount: Int

    static func target(pointerX: CGFloat, appTotal: Int, folderTotal: Int,
                       hasUtilities: Bool, incomingApps: Int, incomingFolders: Int,
                       preview: Self?) -> Self {
        var x = pointerX
        // Map the expanded preview back to the original slots to avoid oscillating targets.
        if let preview {
            let appGapStart = CGFloat(preview.appIndex) * 32
            let folderStart = CGFloat(appTotal + preview.appCount) * 32
                + (appTotal + preview.appCount > 0 && hasUtilities ? 4 : 0)
            let folderGapStart = folderStart + CGFloat(preview.folderIndex) * 32
            if x >= folderGapStart {
                x -= min(CGFloat(preview.folderCount) * 32, x - folderGapStart)
            }
            if x >= appGapStart {
                x -= min(CGFloat(preview.appCount) * 32, x - appGapStart)
            }
            if appTotal == 0 && preview.appCount > 0 && hasUtilities, x > 0 { x = max(0, x - 4) }
        }
        let folderStart = CGFloat(appTotal) * 32 + (appTotal > 0 && hasUtilities ? 4 : 0)
        return Self(appIndex: min(appTotal, max(0, Int((x / 32).rounded()))),
                    folderIndex: min(folderTotal, max(0, Int(((x - folderStart) / 32).rounded()))),
                    appCount: incomingApps, folderCount: incomingFolders)
    }
}

enum FavoriteShelfDrop {
    static func supportedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { original in
            guard original.isFileURL else { return nil }
            var url = original.standardizedFileURL
            if (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true {
                guard let resolved = try? URL(resolvingAliasFileAt: url, options: .withoutUI) else { return nil }
                url = resolved
            }
            url = url.resolvingSymlinksInPath()
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  seen.insert(url.path).inserted else { return nil }
            if url.pathExtension.lowercased() == "app" {
                guard let info = Bundle(url: url)?.infoDictionary, !info.isEmpty else { return nil }
            } else if (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true {
                return nil
            }
            return url
        }
    }
}
