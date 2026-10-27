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
        let step = FavoriteMagnificationLayout.itemStep
        let separatorWidth = step - 28
        var x = pointerX
        // Map the expanded preview back to the original slots to avoid oscillating targets.
        if let preview {
            let appGapStart = CGFloat(preview.appIndex) * step
            let folderStart = CGFloat(appTotal + preview.appCount) * step
                + (appTotal + preview.appCount > 0 && hasUtilities ? separatorWidth : 0)
            let folderGapStart = folderStart + CGFloat(preview.folderIndex) * step
            if x >= folderGapStart {
                x -= min(CGFloat(preview.folderCount) * step, x - folderGapStart)
            }
            if x >= appGapStart {
                x -= min(CGFloat(preview.appCount) * step, x - appGapStart)
            }
            if appTotal == 0 && preview.appCount > 0 && hasUtilities, x > 0 { x = max(0, x - separatorWidth) }
        }
        let folderStart = CGFloat(appTotal) * step + (appTotal > 0 && hasUtilities ? separatorWidth : 0)
        return Self(appIndex: min(appTotal, max(0, Int((x / step).rounded()))),
                    folderIndex: min(folderTotal, max(0, Int(((x - folderStart) / step).rounded()))),
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
