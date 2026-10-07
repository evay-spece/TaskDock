import CoreServices
import Foundation

struct FinderSidebarFavorite {
    let name: String
    let url: URL?
}

enum FinderSidebarFavoritesService {
    /// Read Finder's current Personal Favorites when the context menu opens.
    /// This deprecated read-only API still works on the current macOS release.
    static func favorites() -> [FinderSidebarFavorite] {
        guard let list = LSSharedFileListCreate(nil,
            kLSSharedFileListFavoriteItems.takeUnretainedValue(), nil)?.takeRetainedValue(),
              let items = LSSharedFileListCopySnapshot(list, nil)?.takeRetainedValue()
                as? [LSSharedFileListItem] else { return [] }

        return items.compactMap { item in
            let name = LSSharedFileListItemCopyDisplayName(item).takeRetainedValue() as String
            guard !name.isEmpty else { return nil }
            let url = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?
            return FinderSidebarFavorite(name: name, url: url)
        }
    }
}
