@main
struct RecentAppDisplaySelfTest {
    static func main() {
        let history = Array(0..<30)
        let favorites: Set<Int> = [0, 1, 3, 7, 12, 18]
        let visible = RecentAppDisplayPolicy.visible(from: history,
            excluding: { favorites.contains($0) })
        precondition(visible == [2, 4, 5, 6, 8, 9, 10, 11, 13, 14])
        precondition(RecentAppDisplayPolicy.visible(from: history,
            excluding: { _ in true }).isEmpty)
        precondition(RecentAppDisplayPolicy.visible(from: history,
            excluding: { _ in false }, limit: 0).isEmpty)
        print("RECENT_APP_DISPLAY_OK")
    }
}
