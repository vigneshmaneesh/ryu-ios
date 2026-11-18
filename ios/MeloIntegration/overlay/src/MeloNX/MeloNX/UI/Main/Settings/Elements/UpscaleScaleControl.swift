import SwiftUI

enum UpscaleRatio: Float, CaseIterable, Identifiable {
    case native = 1.0
    case ultraQuality = 1.3
    case quality = 1.5
    case balanced = 1.7
    case performance = 2.0
    case ultraPerformance = 3.0

    var id: Float { rawValue }
    var name: String {
        switch self {
        case .native: return "Native Res"
        case .ultraQuality: return "Ultra Quality"
        case .quality: return "Quality"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        case .ultraPerformance: return "Ultra Performance"
        }
    }
    var label: String { "\(name) · \(String(format: "%.1f", rawValue))x" }

    static func label(for factor: Float) -> String {
        if factor >= 4 { return "Host Display" }
        return allCases.first { abs($0.rawValue - factor) < 0.025 }?.label
            ?? "Custom · \(String(format: "%.1f", factor))x"
    }
}

struct MetalFxScaleControl: View {
    @Binding var value: Float

    private var sliderValue: Binding<Float> {
        Binding(get: { value >= 4 ? 3.1 : value },
                set: { value = $0 >= 3.05 ? 4 : ($0 * 10).rounded() / 10 })
    }

    var body: some View {
        Picker("MetalFX Output Scale", selection: $value) {
            ForEach(UpscaleRatio.allCases) { ratio in
                Text(ratio.label).tag(ratio.rawValue)
            }
            if value < 4 && !UpscaleRatio.allCases.contains(where: { abs($0.rawValue - value) < 0.025 }) {
                Text(UpscaleRatio.label(for: value)).tag(value)
            }
            Text("Host Display (Auto)").tag(Float(4))
        }
        .pickerStyle(.menu)
        SliderRow("Fine Adjustment", value: sliderValue, range: 1...3.1,
                  step: 0.1, minLabel: "Native · 1.0x", maxLabel: "Host",
                  format: "%.1f", maximumValueDisplay: "Host")
        Text("Output/input scale labels. This changes the MetalFX output scale, not the game's render resolution. 1.0x bypasses upscaling; Host fits the display.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct UpscaleRatioGuide: View {
    var body: some View {
        DisclosureGroup("Scaling Quality Guide") {
            ForEach(UpscaleRatio.allCases) { ratio in
                LabeledContent(ratio.name, value: String(format: "%.1fx", ratio.rawValue))
            }
            Text("These names describe output/input ratios. FSR fits the game image to your display; its sharpness slider controls sharpening, not the scale ratio.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
