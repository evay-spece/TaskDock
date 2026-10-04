import Foundation

@main
struct FusionDisplaySelfTest {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000)
        let candidates = [
            FusionDisplayPolicy.Candidate(id: "a", appKey: "A", isFocused: false, isAllowedOnRight: true),
            FusionDisplayPolicy.Candidate(id: "b", appKey: "B", isFocused: true, isAllowedOnRight: true),
            FusionDisplayPolicy.Candidate(id: "c", appKey: "C", isFocused: false, isAllowedOnRight: true),
            FusionDisplayPolicy.Candidate(id: "hidden", appKey: "H", isFocused: false, isAllowedOnRight: false)
        ]
        let dates = ["a": now.addingTimeInterval(-20), "b": now.addingTimeInterval(-60),
                     "c": now.addingTimeInterval(-40), "hidden": now]
        precondition(FusionDisplayPolicy.recentWindowIDs(
            from: candidates, focusedAt: dates, minimumWindowCount: 2, now: now
        ) == Set(["a", "b"]))
        precondition(FusionDisplayPolicy.recentWindowIDs(
            from: candidates, focusedAt: dates, minimumWindowCount: 1, now: now
        ).isEmpty)
        precondition(FusionDisplayPolicy.recentWindowIDs(
            from: candidates, focusedAt: ["a": now.addingTimeInterval(-301)],
            minimumWindowCount: 2, now: now
        ).isEmpty)
        precondition(FusionDisplayPolicy.displayCount(appKeys: ["A", "A", "A", "B", "B"], collapseThreshold: 3) == 3)
        precondition(FusionDisplayPolicy.displayCount(appKeys: ["A", "A", "A"], collapseThreshold: 4) == 3)
        print("FUSION_DISPLAY_OK")
    }
}
