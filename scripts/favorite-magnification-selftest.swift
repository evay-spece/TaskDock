import Foundation

@main
struct FavoriteMagnificationSelfTest {
    static func main() {
        let idle = FavoriteMagnificationLayout(count: 9, pointerX: nil)
        precondition(FavoriteMagnificationLayout.sideClearance(for: 1) == 108)
        precondition(FavoriteMagnificationLayout.idleSideClearance(for: 1) == 31)
        let favoriteLaneLimit = TaskbarFavoriteLaneLayout.contentWidth(
            appCount: 15, folderCount: 1)
        precondition(favoriteLaneLimit == 548)
        precondition(TaskbarFavoriteLaneLayout.flowWidth(
            contentWidth: TaskbarFavoriteLaneLayout.contentWidth(
                appCount: 16, folderCount: 1), limit: favoriteLaneLimit) == favoriteLaneLimit,
            "Adding a favorite must not push recent apps or task items")
        precondition(TaskbarFavoriteLaneLayout.flowWidth(
            contentWidth: TaskbarFavoriteLaneLayout.contentWidth(
                appCount: 14, folderCount: 1), limit: favoriteLaneLimit) == 516,
            "Removing a favorite may pull the right-hand items left")
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
        precondition(FavoriteShelfReorderTarget.index(source: 2, count: 8,
            translation: 15.9, itemStep: 32) == nil)
        precondition(FavoriteShelfReorderTarget.index(source: 2, count: 8,
            translation: 16, itemStep: 32) == 3)
        precondition(FavoriteShelfReorderTarget.index(source: 2, count: 8,
            translation: 14, itemStep: 32, previewIndex: 3) == 3,
            "A small pointer wobble must not retract the preview")
        precondition(FavoriteShelfReorderTarget.index(source: 2, count: 8,
            translation: 12, itemStep: 32, previewIndex: 3) == nil)
        precondition(FavoriteShelfReorderTarget.index(source: 2, count: 8,
            translation: 4 * 32, itemStep: 32) == 6)
        precondition(FavoriteShelfReorderTarget.index(source: 6, count: 8,
            translation: -5 * 32, itemStep: 32) == 1)
        precondition(FavoriteShelfReorderTarget.index(source: 2, count: 8,
            translation: 1000, itemStep: 32) == 7)
        precondition(FavoriteShelfReorderTarget.index(source: 2, count: 8,
            translation: -1000, itemStep: 32) == 0)
        precondition(FavoriteShelfReorderTarget.index(source: 2, count: 8,
            translation: 0, itemStep: 32) == nil)
        for source in 0..<8 {
            for target in 0..<8 where source != target {
                let translation = CGFloat(target - source) * 32
                precondition(FavoriteShelfReorderTarget.index(source: source, count: 8,
                    translation: translation, itemStep: 32) == target,
                    "A direct multi-slot move must land in the previewed slot")
                let reversedTarget = min(7, max(0, source - (target - source)))
                precondition(FavoriteShelfReorderTarget.index(source: source, count: 8,
                    translation: -translation, itemStep: 32)
                    == (reversedTarget == source ? nil : reversedTarget),
                    "Reversing a move must immediately follow the new pointer")
            }
        }
        let quieter = FavoriteMagnificationLayout(count: 9, pointerX: 4.5 * 32,
            peakScale: 1.35)
        precondition(quieter.scales.max()! <= 1.35 && quieter.scales.max()! > 1,
            "Reduced motion keeps hover feedback with a smaller peak")
        precondition(abs(FavoriteMagnificationLayout.maximumScale - 2.0) < 0.001)
        precondition(abs(FavoriteMagnificationLayout.gapGrowthPerScale - 1.25) < 0.001)
        for sizeScale: CGFloat in [0.8, 1, 1.4, 2] {
            for index in 0..<11 where index != 8 {
                let center = ((CGFloat(index) + 0.5) * 32 - (index > 8 ? 28 : 0)) * sizeScale
                precondition(FavoriteMagnificationLayout.hoveredItemIndex(pointerX: center,
                    count: 11, sizeScale: sizeScale, separatorIndices: [8]) == index,
                    "Name must match compacted App, folder and trash slots")
            }
        }

        let separated = FavoriteMagnificationLayout(
            count: 9, pointerX: 4.5 * 32, separatorIndices: [4]
        )
        let separatedIdle = FavoriteMagnificationLayout(
            count: 9, pointerX: nil, separatorIndices: [4]
        )
        for scale: CGFloat in [0.8, 1, 1.4, 2] {
            for pointer: CGFloat? in [nil, 2.5 * 32 * scale, 6.5 * 32 * scale] {
                let layout = FavoriteMagnificationLayout(
                    count: 9, pointerX: pointer, sizeScale: scale, separatorIndices: [4])
                for (source, destination) in [(2, 1), (2, 3), (6, 5), (5, 6)] {
                    let previewOffset = layout.reorderPreviewOffset(
                        from: source, to: destination, sizeScale: scale)
                    let previewCenter = layout.visualGeometry(at: source, sizeScale: scale,
                        dragOffset: previewOffset, isNoWindow: true).centerX
                    let committedCenter = layout.visualGeometry(at: destination, sizeScale: scale,
                        dragOffset: 0, isNoWindow: true).centerX
                    precondition(abs(previewCenter - committedCenter) < 0.001,
                        "Neighbor must already occupy its final slot before release")
                }
            }
        }
        precondition(separatedIdle.offsets[3] == 0)
        precondition(separatedIdle.offsets[4] == -14)
        precondition(separatedIdle.offsets[5] == -28)
        let folderCenter = 5.5 * 32 - 28
        let trackedFolder = FavoriteMagnificationLayout.clampedPointerX(
            trackingX: folderCenter + FavoriteMagnificationLayout.sideClearance(for: 1),
            count: 9, sizeScale: 1, separatorCount: 1
        )
        precondition(trackedFolder == folderCenter)
        precondition(abs(FavoriteMagnificationLayout(
            count: 9, pointerX: trackedFolder, separatorIndices: [4]
        ).scales[5] - FavoriteMagnificationLayout.maximumScale) < 0.001)
        precondition(separated.scales[4] == 1)
        precondition(separated.scales[3] > 1)
        precondition(separated.scales[5] > 1)
        for index in 1..<9 {
            let centerSpacing = 32 + separated.offsets[index] - separated.offsets[index - 1]
            let previousWidth = index - 1 == 4 ? 1 : 26 * separated.scales[index - 1]
            let currentWidth = index == 4 ? 1 : 26 * separated.scales[index]
            precondition(centerSpacing + 0.001 >= (previousWidth + currentWidth) / 2 + 3)
        }
        for pointer in stride(from: CGFloat(2 * 32), through: 8 * 32, by: 0.25) {
            let left = FavoriteMagnificationLayout(
                count: 9, pointerX: pointer, separatorIndices: [4]
            )
            let right = FavoriteMagnificationLayout(
                count: 9, pointerX: pointer + 0.25, separatorIndices: [4]
            )
            for index in 0..<9 where index != 4 {
                precondition(abs(left.scales[index] - right.scales[index]) < 0.015)
                precondition(abs(left.offsets[index] - right.offsets[index]) < 0.8,
                             "separator transition jumped at \(pointer), item \(index)")
            }
        }

        let centered = FavoriteMagnificationLayout(count: 9, pointerX: 2.5 * 32)
        let idleIndicator = idle.visualGeometry(at: 2, sizeScale: 1, dragOffset: 0, isNoWindow: true)
        precondition(idleIndicator.indicatorWidth == FavoriteMagnificationLayout.indicatorDiameter)
        let raisedIndicator = centered.visualGeometry(at: 2, sizeScale: 1, dragOffset: 0, isNoWindow: true)
        let draggedIndicator = centered.visualGeometry(at: 2, sizeScale: 1, dragOffset: 17, isNoWindow: true)
        for translation in stride(from: CGFloat(-48), through: 80, by: 4) {
            let pointer = 2.5 * 32 + translation
            let moving = FavoriteMagnificationLayout(count: 9, pointerX: pointer)
            let compensatedOffset = translation + centered.offsets[2] - moving.offsets[2]
            let movingCenter = moving.visualGeometry(at: 2, sizeScale: 1,
                dragOffset: compensatedOffset, isNoWindow: true).centerX
            precondition(abs(movingCenter - raisedIndicator.centerX - translation) < 0.001,
                "Dragged icon must track pointer despite changing magnification")
        }
        precondition(raisedIndicator.iconBottomY > idleIndicator.iconBottomY)
        precondition(raisedIndicator.indicatorCenterY > idleIndicator.indicatorCenterY)
        precondition(raisedIndicator.indicatorWidth > idleIndicator.indicatorWidth)
        precondition(abs(raisedIndicator.centerX - draggedIndicator.centerX + 17) < 0.001)
        precondition(abs(raisedIndicator.iconBottomY - raisedIndicator.indicatorCenterY - 2.5) < 0.001)
        precondition(abs(centered.scales[2] - FavoriteMagnificationLayout.maximumScale) < 0.001)
        precondition(centered.scales[1] > centered.scales[0])
        precondition(centered.scales[3] > centered.scales[4])
        precondition(abs(centered.scales[1] - (1 + (0.923 * 2.25 - 1) * 0.8)) < 0.03)
        precondition(abs(centered.scales[0] - (1 + (0.719 * 2.25 - 1) * 0.8)) < 0.05)
        precondition(FavoriteMagnificationLayout(
            count: 9, pointerX: 2.5 * 32
        ).scales[7] == 1)
        precondition(abs(centered.scales[1] - centered.scales[3]) < 0.001)
        let magnifiedEdgeGap = 32 + centered.offsets[3] - centered.offsets[2]
            - 26 * (centered.scales[2] + centered.scales[3]) / 2
        let expectedEdgeGap = 6 + FavoriteMagnificationLayout.gapGrowthPerScale
            * (centered.scales[2] + centered.scales[3] - 2) / 2
        precondition(abs(magnifiedEdgeGap - expectedEdgeGap) < 0.001)
        let recording = FavoriteMagnificationLayout(
            count: 8, pointerX: (3.14 + 0.5) * 32
        )
        let recordedIconWidths: [CGFloat] = [50, 74, 98, 108, 102, 82, 55, 48]
        for index in recordedIconWidths.indices {
            let reducedScale = 1 + (recordedIconWidths[index] / 48 - 1) * 0.8
            precondition(abs(recording.scales[index] - reducedScale) < 0.035)
        }
        precondition(centered.offsets[2] >= 0)
        for index in 1..<9 {
            let centerSpacing = 32 + centered.offsets[index] - centered.offsets[index - 1]
            let meanExcess = (centered.scales[index - 1] + centered.scales[index] - 2) / 2
            let minimumSpacing = 26 * (centered.scales[index - 1] + centered.scales[index]) / 2
                + 6 + FavoriteMagnificationLayout.gapGrowthPerScale * meanExcess
            precondition(centerSpacing + 0.001 >= minimumSpacing)
        }
        for pointer in stride(from: CGFloat.zero, through: 9 * 32, by: 4) {
            let layout = FavoriteMagnificationLayout(count: 9, pointerX: pointer)
            for index in 1..<9 {
                let centerSpacing = 32 + layout.offsets[index] - layout.offsets[index - 1]
                let meanExcess = (layout.scales[index - 1] + layout.scales[index] - 2) / 2
                let minimumSpacing = 26 * (layout.scales[index - 1] + layout.scales[index]) / 2
                    + 6 + FavoriteMagnificationLayout.gapGrowthPerScale * meanExcess
                precondition(centerSpacing + 0.001 >= minimumSpacing)
            }
        }

        let before = FavoriteMagnificationLayout(count: 9, pointerX: 3 * 32 - 0.1)
        let after = FavoriteMagnificationLayout(count: 9, pointerX: 3 * 32 + 0.1)
        let maximumBoundaryMovement = zip(before.offsets, after.offsets)
            .map { abs($0 - $1) }.max() ?? 0
        precondition(maximumBoundaryMovement < 0.5,
                     "boundary movement \(maximumBoundaryMovement)")
        let finderAtLeft = FavoriteMagnificationLayout(count: 9, pointerX: 0.5 * 32)
        let finderAtMiddle = FavoriteMagnificationLayout(count: 9, pointerX: 3.5 * 32)
        let finderAtRight = FavoriteMagnificationLayout(count: 9, pointerX: 8.5 * 32)
        precondition(finderAtLeft.offsets[0] > finderAtMiddle.offsets[0])
        precondition(finderAtMiddle.offsets[0] > finderAtRight.offsets[0],
                     "Finder must follow the pointer instead of sticking to the left edge")

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
            let maximumLabelTop = (6 + 4.5 + FavoriteMagnificationLayout.iconSize
                * FavoriteMagnificationLayout.maximumScale + 5
                + FavoriteMagnificationLayout.hoverLabelHeight) * sizeScale
            precondition(38 * sizeScale
                + FavoriteMagnificationLayout.headroom(for: sizeScale) > maximumLabelTop)
            for pointer in stride(from: CGFloat.zero, through: 9 * step, by: step / 8) {
                let layout = FavoriteMagnificationLayout(count: 9, pointerX: pointer, sizeScale: sizeScale)
                let clearance = FavoriteMagnificationLayout.sideClearance(for: sizeScale)
                for index in 0..<9 {
                    let center = (CGFloat(index) + 0.5) * step + layout.offsets[index]
                    let radius = icon * layout.scales[index] / 2
                    precondition(center + radius <= 9 * step + clearance,
                                 "right-edge overflow \(center + radius - 9 * step - clearance) at pointer \(pointer), index \(index)")
                }
                for index in 1..<9 {
                    let centerSpacing = step + layout.offsets[index] - layout.offsets[index - 1]
                    let meanExcess = (layout.scales[index - 1] + layout.scales[index] - 2) / 2
                    let minimumSpacing = icon * (layout.scales[index - 1] + layout.scales[index]) / 2
                        + (6 + FavoriteMagnificationLayout.gapGrowthPerScale * meanExcess) * sizeScale
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
                        precondition(geometry.centerX + radius
                            <= CGFloat(count) * step + clearance,
                                     "right overflow \(geometry.centerX + radius - CGFloat(count) * step - clearance), count \(count), pointer \(pointer), index \(index)")
                    }
                }
            }
        }
        print("FAVORITE_MAGNIFICATION_OK")
    }
}
