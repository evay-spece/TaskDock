import AppKit
import SwiftUI

/// Uses the system SwiftUI slider, including the current macOS glass treatment.
/// Only the preset marker and light snapping are app-specific.
struct ReleaseTunedSlider: View {
    @Binding var value: Double
    @State private var snapped = false
    let range: ClosedRange<Double>
    let defaultValue: Double

    init<V: BinaryFloatingPoint>(value: Binding<V>, in range: ClosedRange<V>, defaultValue: Double) {
        _value = Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = V($0) })
        self.range = Double(range.lowerBound)...Double(range.upperBound)
        self.defaultValue = min(Double(range.upperBound), max(Double(range.lowerBound), defaultValue))
    }

    static func preset(_ key: String, fallback: Double) -> Double {
        (ReleaseAppearanceSnapshot.values[key] as? NSNumber)?.doubleValue ?? fallback
    }

    private var sliderValue: Binding<Double> {
        Binding(get: { value }, set: { proposed in
            let near = abs(proposed - defaultValue) <= (range.upperBound - range.lowerBound) * 0.012
            if near && !snapped {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            snapped = near
            value = near ? defaultValue : proposed
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            Slider(value: sliderValue, in: range, onEditingChanged: { editing in
                if !editing { snapped = false }
            })
            .controlSize(.regular)
            .frame(minHeight: 28)

            GeometryReader { geometry in
                let x = 12 + max(0, geometry.size.width - 24)
                    * (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)
                VStack(spacing: 1) {
                    Circle().fill(Color.secondary.opacity(0.5)).frame(width: 3, height: 3)
                    Text("默认").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .position(x: min(max(x, 14), geometry.size.width - 14), y: 8)
            }
            .frame(height: 18)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
