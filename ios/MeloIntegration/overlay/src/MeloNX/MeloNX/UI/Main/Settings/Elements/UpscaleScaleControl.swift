import SwiftUI

enum UpscalePreset: String, CaseIterable, Identifiable {
    case manual
    case native
    case ultraQuality
    case quality
    case balanced
    case performance
    case ultraPerformance

    var id: String { rawValue }

    var ratio: Float {
        switch self {
        case .manual, .native: return 1
        case .ultraQuality: return 1.3
        case .quality: return 1.5
        case .balanced: return 1.7
        case .performance: return 2
        case .ultraPerformance: return 3
        }
    }

    var renderScale: Float { 1 / ratio }

    var name: String {
        switch self {
        case .manual: return "Manual"
        case .native: return "Native Res"
        case .ultraQuality: return "Ultra Quality"
        case .quality: return "Quality"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        case .ultraPerformance: return "Ultra Performance"
        }
    }
}

struct UpscalePresetControl: View {
    @Binding var preset: UpscalePreset

    var body: some View {
        Picker("Upscaling Preset", selection: $preset) {
            ForEach(UpscalePreset.allCases) { option in
                if option == .manual {
                    Text(option.name).tag(option)
                } else {
                    Text("\(option.name) · \(option.ratio, specifier: "%.1f")x").tag(option)
                }
            }
        }
        .pickerStyle(.menu)
        if preset != .manual {
            Text("Ratios are relative to the game's native resolution. Relaunch the game to apply.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MetalFxScaleControl: View {
    @Binding var value: Float

    private var sliderValue: Binding<Float> {
        Binding(get: { value >= 4 ? 3.1 : value },
                set: { value = $0 >= 3.05 ? 4 : ($0 * 10).rounded() / 10 })
    }

    var body: some View {
        SliderRow("MetalFX Output Scale", value: sliderValue, range: 1...3.1,
                  step: 0.1, minLabel: "Bypass · 1.0x", maxLabel: "Host",
                  format: "%.1f", maximumValueDisplay: "Host")
    }
}
