import Foundation

@main
struct DockCompanionSizingSelfTest {
    static func main() {
        precondition(DockCompanionSizing.scale(for: 41) == 1)
        precondition(DockCompanionSizing.itemHeight(for: 41) == 31)
        precondition(DockCompanionSizing.panelHeight(for: 41) == 61)

        let largeDockHeight: CGFloat = 72
        precondition(DockCompanionSizing.scale(for: largeDockHeight) > 1.7)
        precondition(DockCompanionSizing.itemHeight(for: largeDockHeight) > 52)
        precondition(DockCompanionSizing.preferredItemWidth(for: largeDockHeight) > 300)
        precondition(DockCompanionSizing.contentScale(for: largeDockHeight) <= 1.5)

        precondition(!DockCompanionSizing.isTemporarilyMagnified(
            configuredTileSize: 30,
            observedItemWidths: [32, 32, 16]
        ))
        precondition(DockCompanionSizing.isTemporarilyMagnified(
            configuredTileSize: 30,
            observedItemWidths: [32, 51, 67]
        ))
        precondition(!DockCompanionSizing.isTemporarilyMagnified(
            configuredTileSize: 48,
            observedItemWidths: [50, 50, 24]
        ))
        precondition(DockCompanionSizing.isTemporarilyMagnified(
            configuredTileSize: 48,
            observedItemWidths: [50, 67]
        ))

        print("DOCK_COMPANION_SIZING_OK")
    }
}
