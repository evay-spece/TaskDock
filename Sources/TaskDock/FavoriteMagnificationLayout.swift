import CoreGraphics
import Foundation

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
    static let maximumScale: CGFloat = 1.85
    let scales: [CGFloat]
    let offsets: [CGFloat]

    init(count: Int, pointerX: CGFloat?, sizeScale: CGFloat = 1) {
        guard count > 0 else {
            scales = []
            offsets = []
            return
        }
        guard let pointerX else {
            scales = Array(repeating: 1, count: count)
            offsets = Array(repeating: 0, count: count)
            return
        }

        let itemStep = Self.itemStep * sizeScale
        let iconSize = Self.iconSize * sizeScale
        let influenceRadius = itemStep * 3
        let standardDeviation = itemStep * 1.2
        scales = (0..<count).map { index in
            let center = (CGFloat(index) + 0.5) * itemStep
            let distance = abs(pointerX - center)
            let influence = distance >= influenceRadius
                ? 0 : exp(-0.5 * pow(distance / standardDeviation, 2))
            return 1 + (Self.maximumScale - 1) * CGFloat(influence)
        }

        var cumulative = Array(repeating: CGFloat.zero, count: count)
        if count > 1 {
            for index in 1..<count {
                let requiredStep = iconSize * (scales[index - 1] + scales[index]) / 2
                    + 3 * sizeScale
                cumulative[index] = cumulative[index - 1] + max(0, requiredStep - itemStep)
            }
        }

        let position = min(max(pointerX / itemStep - 0.5, 0), CGFloat(count - 1))
        let lower = Int(position)
        let upper = min(lower + 1, count - 1)
        let anchor = cumulative[lower] + (cumulative[upper] - cumulative[lower])
            * (position - CGFloat(lower))
        offsets = cumulative.map { $0 - anchor }
    }

    static func lift(for scale: CGFloat) -> CGFloat {
        -4.5 * (scale - 1) / (maximumScale - 1)
    }

    static func headroom(for sizeScale: CGFloat) -> CGFloat {
        ceil((30 * (maximumScale - 1) + 8) * sizeScale)
    }

    static func sideClearance(for sizeScale: CGFloat) -> CGFloat {
        ceil(25 * sizeScale)
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
            indicatorWidth: (isNoWindow ? 5 : 15) * sizeScale * indicatorScale,
            indicatorHeight: (isNoWindow ? 5 : 2) * sizeScale * indicatorScale
        )
    }
}
