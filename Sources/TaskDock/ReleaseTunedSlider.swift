import AppKit
import SwiftUI

/// Continuous system slider with the release preset marked and lightly snapped.
struct ReleaseTunedSlider: View {
    @Binding var value: Double
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

    var body: some View {
        VStack(spacing: 0) {
            NativeSlider(value: $value, range: range, preset: defaultValue)
                .frame(height: 24)
            GeometryReader { geometry in
                let x = 9 + (geometry.size.width - 18)
                    * (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)
                VStack(spacing: 1) {
                    Circle().fill(Color.secondary.opacity(0.5)).frame(width: 3, height: 3)
                    Text("默认").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .position(x: min(max(x, 14), geometry.size.width - 14), y: 8)
            }.frame(height: 18)
        }
    }

    private struct NativeSlider: NSViewRepresentable {
        @Binding var value: Double
        let range: ClosedRange<Double>
        let preset: Double
        func makeCoordinator() -> Coordinator { Coordinator(self) }
        func makeNSView(context: Context) -> NSSlider {
            let slider = NSSlider(value: value, minValue: range.lowerBound,
                maxValue: range.upperBound, target: context.coordinator,
                action: #selector(Coordinator.changed(_:)))
            slider.isContinuous = true
            slider.numberOfTickMarks = 0
            slider.controlSize = .regular
            return slider
        }
        func updateNSView(_ slider: NSSlider, context: Context) {
            context.coordinator.owner = self
            slider.isEnabled = context.environment.isEnabled
            slider.doubleValue = value
        }
        final class Coordinator: NSObject {
            var owner: NativeSlider
            var snapped = false
            init(_ owner: NativeSlider) { self.owner = owner }
            @objc func changed(_ sender: NSSlider) {
                let near = abs(sender.doubleValue - owner.preset)
                    <= (owner.range.upperBound - owner.range.lowerBound) * 0.012
                if near && !snapped {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                snapped = near
                let result = near ? owner.preset : sender.doubleValue
                sender.doubleValue = result
                owner.value = result
            }
        }
    }
}
