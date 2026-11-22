import SwiftUI

struct DeviceGyroSettingsView: View {
    @Binding var settings: DeviceMotionSettings
    @State private var previewID = UUID()

    private var orientation: Binding<DeviceMotionOrientation> {
        Binding(get: { settings.orientation }, set: { value in
            var updated = settings
            updated.orientation = value
            updated.neutralUp = nil
            settings = updated
        })
    }

    var body: some View {
        Section {
            liveTilt

            Picker("Gyro Orientation", selection: orientation) {
                ForEach(DeviceMotionOrientation.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            SliderRow("Sensitivity", value: $settings.sensitivity, range: 0.5...2, step: 0.1,
                      minLabel: "Low", maxLabel: "High", format: "%.1f", suffix: "×")
            SliderRow("Center Dead Zone", value: $settings.deadZone, range: 0...15, step: 1,
                      minLabel: "None", maxLabel: "15°", format: "%.0f", suffix: "°")
            Toggle("Invert Steering", isOn: $settings.invertSteering)
            Button("Reset Gyro Settings") { settings = DeviceMotionSettings() }
        } header: {
            Text("Device Gyro")
        } footer: {
            Text("Hold the device as you do while playing, then tap Recenter. The dot shows the resulting tilt.")
        }
    }

    private var liveTilt: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            if let (sample, screen) = DeviceMotionFeed.shared.snapshot() {
                let output = settings.process(sample, screen: screen)
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Live Tilt", value: settings.resolvedOrientation(screen).displayName)
                    tiltIndicator(roll: output.rollDegrees, pitch: output.pitchDegrees)
                    Text("Roll \(output.rollDegrees, specifier: "%.0f")° · Pitch \(output.pitchDegrees, specifier: "%.0f")°")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Recenter") { settings.recenter(sample, screen: screen) }
                        .buttonStyle(.borderless)
                }
            } else {
                LabeledContent("Live Tilt", value: DeviceMotionFeed.shared.isAvailable ? "Waiting for motion data" : "Gyro unavailable")
            }
        }
        .onAppear { DeviceMotionFeed.shared.setPreviewActive(true, id: previewID) }
        .onDisappear { DeviceMotionFeed.shared.setPreviewActive(false, id: previewID) }
    }

    private func tiltIndicator(roll: Float, pitch: Float) -> some View {
        GeometryReader { proxy in
            let horizontal = CGFloat(min(max(roll / 45, -1), 1))
            let vertical = CGFloat(min(max(pitch / 45, -1), 1))
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.secondary.opacity(0.10))
                Rectangle().fill(.secondary.opacity(0.28)).frame(width: 1)
                Rectangle().fill(.secondary.opacity(0.28)).frame(height: 1)
                Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                    .offset(x: horizontal * (proxy.size.width / 2 - 10),
                            y: -vertical * (proxy.size.height / 2 - 10))
            }
        }
        .frame(height: 86)
        .accessibilityHidden(true)
    }
}

private extension DeviceMotionOrientation {
    var displayName: String {
        switch self {
        case .automatic: return String(localized: "Follow Game Screen")
        case .portrait: return String(localized: "Portrait")
        case .portLeft: return String(localized: "Landscape · Port Left")
        case .portRight: return String(localized: "Landscape · Port Right")
        case .portraitUpsideDown: return String(localized: "Upside-Down Portrait")
        }
    }
}
