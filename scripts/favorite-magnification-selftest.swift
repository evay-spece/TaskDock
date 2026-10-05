import Foundation

@main
struct FavoriteMagnificationSelfTest {
    static func main() {
        let idle = FavoriteMagnificationLayout(count: 9, pointerX: nil)
        precondition(FavoriteMagnificationLayout.sideClearance(for: 1) == 25)
        let safety = FavoriteMagnificationLayout.sideClearance(for: 1)
        let rightEdgePointer = FavoriteMagnificationLayout.clampedPointerX(
            trackingX: 9 * 32 + 2 * safety,
            count: 9,
            sizeScale: 1
        )
        precondition(rightEdgePointer == 8.5 * 32)
        precondition(FavoriteMagnificationLayout(count: 9, pointerX: rightEdgePointer).scales[8]
            == FavoriteMagnificationLayout.maximumScale)
        precondition(idle.scales.allSatisfy { $0 == 1 })
        precondition(idle.offsets.allSatisfy { $0 == 0 })

        let centered = FavoriteMagnificationLayout(count: 9, pointerX: 2.5 * 32)
        let idleIndicator = idle.visualGeometry(at: 2, sizeScale: 1, dragOffset: 0, isNoWindow: true)
        let raisedIndicator = centered.visualGeometry(at: 2, sizeScale: 1, dragOffset: 0, isNoWindow: true)
        let draggedIndicator = centered.visualGeometry(at: 2, sizeScale: 1, dragOffset: 17, isNoWindow: true)
        precondition(raisedIndicator.iconBottomY > idleIndicator.iconBottomY)
        precondition(raisedIndicator.indicatorCenterY > idleIndicator.indicatorCenterY)
        precondition(raisedIndicator.indicatorWidth > idleIndicator.indicatorWidth)
        precondition(abs(raisedIndicator.centerX - draggedIndicator.centerX + 17) < 0.001)
        precondition(abs(raisedIndicator.iconBottomY - raisedIndicator.indicatorCenterY - 2.5) < 0.001)
        precondition(abs(centered.scales[2] - FavoriteMagnificationLayout.maximumScale) < 0.001)
        precondition(centered.scales[1] > centered.scales[0])
        precondition(centered.scales[3] > centered.scales[4])
        precondition(centered.scales[1] > 1.6)
        precondition(centered.scales[0] > 1.2)
        precondition(abs(centered.offsets[2]) < 0.001)
        for index in 1..<9 {
            let centerSpacing = 32 + centered.offsets[index] - centered.offsets[index - 1]
            let minimumSpacing = 26 * (centered.scales[index - 1] + centered.scales[index]) / 2 + 3
            precondition(centerSpacing + 0.001 >= minimumSpacing)
        }
        for pointer in stride(from: CGFloat.zero, through: 9 * 32, by: 4) {
            let layout = FavoriteMagnificationLayout(count: 9, pointerX: pointer)
            for index in 1..<9 {
                let centerSpacing = 32 + layout.offsets[index] - layout.offsets[index - 1]
                let minimumSpacing = 26 * (layout.scales[index - 1] + layout.scales[index]) / 2 + 3
                precondition(centerSpacing + 0.001 >= minimumSpacing)
            }
        }

        let before = FavoriteMagnificationLayout(count: 9, pointerX: 3 * 32 - 0.1)
        let after = FavoriteMagnificationLayout(count: 9, pointerX: 3 * 32 + 0.1)
        precondition(zip(before.offsets, after.offsets).allSatisfy { abs($0 - $1) < 0.2 })

        for sizeScale in [CGFloat(34.0 / 38), CGFloat(54.0 / 38), CGFloat(64.0 / 38)] {
            let step = 32 * sizeScale
            let icon = 26 * sizeScale
            let rightmostPointer = FavoriteMagnificationLayout.clampedPointerX(
                trackingX: 9 * step + 2 * FavoriteMagnificationLayout.sideClearance(for: sizeScale),
                count: 9,
                sizeScale: sizeScale
            )
            precondition(abs(rightmostPointer - 8.5 * step) < 0.001)
            precondition(abs(FavoriteMagnificationLayout(
                count: 9, pointerX: rightmostPointer, sizeScale: sizeScale
            ).scales[8] - FavoriteMagnificationLayout.maximumScale) < 0.001)
            precondition(FavoriteMagnificationLayout.headroom(for: sizeScale)
                > (30 * (FavoriteMagnificationLayout.maximumScale - 1) + 4.5) * sizeScale)
            for pointer in stride(from: CGFloat.zero, through: 9 * step, by: step / 8) {
                let layout = FavoriteMagnificationLayout(count: 9, pointerX: pointer, sizeScale: sizeScale)
                let clearance = FavoriteMagnificationLayout.sideClearance(for: sizeScale)
                for index in 0..<9 {
                    let center = (CGFloat(index) + 0.5) * step + layout.offsets[index]
                    let radius = icon * layout.scales[index] / 2
                    precondition(center - radius >= -clearance)
                    precondition(center + radius <= 9 * step + clearance)
                }
                for index in 1..<9 {
                    let centerSpacing = step + layout.offsets[index] - layout.offsets[index - 1]
                    let minimumSpacing = icon * (layout.scales[index - 1] + layout.scales[index]) / 2 + 3 * sizeScale
                    precondition(centerSpacing + 0.001 >= minimumSpacing)
                }
            }
            for count in 1...15 {
                for pointer in stride(from: CGFloat.zero,
                                      through: CGFloat(count) * step,
                                      by: step / 32) {
                    let layout = FavoriteMagnificationLayout(
                        count: count, pointerX: pointer, sizeScale: sizeScale
                    )
                    for index in 0..<count {
                        let geometry = layout.visualGeometry(
                            at: index, sizeScale: sizeScale,
                            dragOffset: 0, isNoWindow: true
                        )
                        let radius = icon * layout.scales[index] / 2
                        let clearance = FavoriteMagnificationLayout.sideClearance(for: sizeScale)
                        precondition(geometry.centerX - radius >= -clearance)
                        precondition(geometry.centerX + radius
                            <= CGFloat(count) * step + clearance)
                    }
                }
            }
        }
        print("FAVORITE_MAGNIFICATION_OK")
    }
}
