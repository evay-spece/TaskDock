import CoreGraphics
import Foundation

enum FavoriteShelfReorderTarget {
    static func index(source: Int, count: Int, translation: CGFloat,
                      itemStep: CGFloat, previewIndex: Int? = nil) -> Int? {
        guard count > 1, (0..<count).contains(source), itemStep > 0,
              translation.isFinite else { return nil }
        let distance = abs(translation) / itemStep
        let crossed = Int(min(CGFloat(count), floor(distance + 0.5)))
        let proposed = min(count - 1, max(0, source + (translation < 0 ? -crossed : crossed)))
        let previous = previewIndex ?? source
        if previous != source, proposed != previous {
            let priorDistance = abs(previous - source)
            if proposed == source, distance > 0.42 { return previous }
            let sameDirection = (previous - source) * (proposed - source) > 0
            if sameDirection, abs(proposed - source) > priorDistance,
               distance < CGFloat(priorDistance) + 0.58 { return previous }
            if sameDirection, abs(proposed - source) < priorDistance,
               distance > CGFloat(priorDistance) - 0.58 { return previous }
        }
        return proposed == source ? nil : proposed
    }
}

enum TaskbarFavoriteLaneLayout {
    static func contentWidth(appCount: Int, folderCount: Int,
                             showsTrash: Bool = true) -> CGFloat {
        let hasUtilities = showsTrash || folderCount > 0
        let separatorCount = appCount > 0 && hasUtilities ? 1 : 0
        let itemCount = appCount + folderCount + (showsTrash ? 1 : 0) + separatorCount
        return CGFloat(itemCount * 32 - separatorCount * 28)
    }

    static func flowWidth(contentWidth: CGFloat, limit: CGFloat) -> CGFloat {
        min(max(0, contentWidth), max(0, limit))
    }
}

struct FavoriteVisualGeometry {
    let centerX: CGFloat
    let iconBottomY: CGFloat
    let indicatorCenterY: CGFloat
    let indicatorWidth: CGFloat
    let indicatorHeight: CGFloat
}

/// Dock-style visual positions. Hit targets remain in their original 32-point slots.
struct FavoriteMagnificationLayout {
    static let itemStep: CGFloat = 32
    static let iconSize: CGFloat = 26
    static let indicatorDiameter: CGFloat = 4
    static let maximumScale: CGFloat = 2.0
    static let influenceRadius: CGFloat = 3.32
    static let influenceExponent: CGFloat = 1.56
    static let gapGrowthPerScale: CGFloat = 1.25
    static let hoverLabelHeight: CGFloat = 31
    let scales: [CGFloat]
    let offsets: [CGFloat]

    init(count: Int, pointerX: CGFloat?, sizeScale: CGFloat = 1,
         separatorIndices: Set<Int> = [], peakScale: CGFloat = Self.maximumScale) {
        guard count > 0 else {
            scales = []
            offsets = []
            return
        }
        let itemStep = Self.itemStep * sizeScale
        let iconSize = Self.iconSize * sizeScale
        let compactOffsets: [CGFloat] = (0..<count).map { index in
            separatorIndices.reduce(CGFloat.zero) { result, separator in
                result - (index > separator ? 28 : index == separator ? 14 : 0) * sizeScale
            }
        }
        let centers = (0..<count).map {
            (CGFloat($0) + 0.5) * itemStep + compactOffsets[$0]
        }
        scales = (0..<count).map { index in
            guard let pointerX else { return 1 }
            if separatorIndices.contains(index) { return 1 }
            let distance = abs(pointerX - centers[index]) / itemStep
            let normalized = max(0, 1 - pow(distance / Self.influenceRadius, 2))
            let influence = pow(normalized, Self.influenceExponent)
            return 1 + (peakScale - 1) * CGFloat(influence)
        }

        var cumulative = Array(repeating: CGFloat.zero, count: count)
        if count > 1 {
            for index in 1..<count {
                let previousWidth = separatorIndices.contains(index - 1)
                    ? 1 * sizeScale : iconSize * scales[index - 1]
                let currentWidth = separatorIndices.contains(index)
                    ? 1 * sizeScale : iconSize * scales[index]
                let desiredGap: CGFloat
                if separatorIndices.contains(index - 1) || separatorIndices.contains(index) {
                    desiredGap = 3 * sizeScale
                } else {
                    let meanExcess = (scales[index - 1] + scales[index] - 2) / 2
                    desiredGap = (Self.itemStep - Self.iconSize
                        + Self.gapGrowthPerScale * meanExcess) * sizeScale
                }
                let requiredStep = (previousWidth + currentWidth) / 2
                    + desiredGap
                // The separator is visually narrow. Compress its empty slot so
                // the magnification wave stays continuous through utilities.
                cumulative[index] = cumulative[index - 1]
                    + requiredStep - (centers[index] - centers[index - 1])
            }
        }
        guard let pointerX else {
            offsets = compactOffsets
            return
        }
        let upper = centers.firstIndex(where: { $0 > pointerX }) ?? count - 1
        let lower = max(0, upper - 1)
        let interpolation = upper == lower ? 0
            : min(max((pointerX - centers[lower]) / (centers[upper] - centers[lower]), 0), 1)
        let anchor = cumulative[lower] + (cumulative[upper] - cumulative[lower]) * interpolation
        let anchoredOffsets = cumulative.map { $0 - anchor }
        offsets = anchoredOffsets.enumerated().map {
            compactOffsets[$0.offset] + $0.element
        }
    }

    static func lift(for scale: CGFloat) -> CGFloat {
        -4.5 * (scale - 1) / (maximumScale - 1)
    }

    static func headroom(for sizeScale: CGFloat, peakScale: CGFloat = maximumScale) -> CGFloat {
        ceil((30 * (peakScale - 1) + 8 + hoverLabelHeight) * sizeScale)
    }

    static func sideClearance(for sizeScale: CGFloat) -> CGFloat {
        ceil(108 * sizeScale)
    }

    static func idleSideClearance(for sizeScale: CGFloat) -> CGFloat {
        ceil(31 * sizeScale)
    }

    static func clampedPointerX(trackingX: CGFloat, count: Int, sizeScale: CGFloat,
                                separatorCount: Int = 0) -> CGFloat {
        guard count > 0 else { return 0 }
        let step = itemStep * sizeScale
        let rowWidth = CGFloat(count) * step - CGFloat(separatorCount) * 28 * sizeScale
        let pointerX = trackingX - sideClearance(for: sizeScale)
        return min(max(pointerX, step / 2), rowWidth - step / 2)
    }

    static func hoveredItemIndex(pointerX: CGFloat, count: Int, sizeScale: CGFloat,
                                 separatorIndices: Set<Int>, excludedIndices: Set<Int> = []) -> Int? {
        (0..<max(0, count)).filter {
            !separatorIndices.contains($0) && !excludedIndices.contains($0)
        }.min { left, right in
            func center(_ index: Int) -> CGFloat {
                let compression = separatorIndices.reduce(CGFloat.zero) { result, separator in
                    result + (index > separator ? 28 : index == separator ? 14 : 0) * sizeScale
                }
                return (CGFloat(index) + 0.5) * itemStep * sizeScale - compression
            }
            return abs(pointerX - center(left)) < abs(pointerX - center(right))
        }
    }

    func reorderPreviewOffset(from sourceIndex: Int, to destinationIndex: Int,
                              sizeScale: CGFloat) -> CGFloat {
        guard scales.indices.contains(sourceIndex), scales.indices.contains(destinationIndex) else { return 0 }
        return CGFloat(destinationIndex - sourceIndex) * Self.itemStep * sizeScale
            + offsets[destinationIndex] - offsets[sourceIndex]
    }

    func visualGeometry(
        at index: Int,
        sizeScale: CGFloat,
        dragOffset: CGFloat,
        isNoWindow: Bool
    ) -> FavoriteVisualGeometry {
        let scale = scales[index]
        let liftY = -Self.lift(for: scale) * sizeScale
        let indicatorScale = 1 + (scale - 1) * 0.5
        return FavoriteVisualGeometry(
            centerX: (CGFloat(index) * Self.itemStep + 15) * sizeScale
                + offsets[index] + dragOffset,
            iconBottomY: 6 * sizeScale + liftY,
            indicatorCenterY: (isNoWindow ? 3.5 : 3) * sizeScale + liftY,
            indicatorWidth: (isNoWindow ? Self.indicatorDiameter : 15) * sizeScale * indicatorScale,
            indicatorHeight: (isNoWindow ? Self.indicatorDiameter : 2) * sizeScale * indicatorScale
        )
    }
}
