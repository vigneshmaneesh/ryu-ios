import Foundation
import simd

nonisolated enum DeviceMotionOrientation: String, Codable, CaseIterable {
    case automatic
    case portrait
    case portLeft
    case portRight
    case portraitUpsideDown

    func screenAxes(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        switch self {
        case .portLeft: return SIMD3(vector.y, -vector.x, vector.z)
        case .portRight: return SIMD3(-vector.y, vector.x, vector.z)
        case .portraitUpsideDown: return SIMD3(-vector.x, -vector.y, vector.z)
        case .automatic, .portrait: return vector
        }
    }
}

nonisolated struct DeviceMotionSample {
    // Specific force points up while the device is held still.
    let up: SIMD3<Float>
    let linearAcceleration: SIMD3<Float>
    let rotationRate: SIMD3<Float>
}

nonisolated struct DeviceMotionOutput {
    let up: SIMD3<Float>
    let accelerometer: SIMD3<Float>
    let gyroscope: SIMD3<Float>

    var rollDegrees: Float { -atan2(up.x, up.y) * (180 / .pi) }
    var pitchDegrees: Float { atan2(up.z, hypot(up.x, up.y)) * (180 / .pi) }
}

nonisolated struct DeviceMotionSettings: Codable, Hashable {
    var orientation: DeviceMotionOrientation = .automatic
    var sensitivity: Float = 1
    var deadZone: Float = 3
    var invertSteering = false
    var neutralUp: SIMD3<Float>?

    func resolvedOrientation(_ screen: DeviceMotionOrientation) -> DeviceMotionOrientation {
        orientation == .automatic ? screen : orientation
    }

    mutating func recenter(_ sample: DeviceMotionSample, screen: DeviceMotionOrientation) {
        let up = resolvedOrientation(screen).screenAxes(sample.up)
        let length = simd_length(up)
        guard length.isFinite, length > 0.5 else { return }
        neutralUp = up / length
    }

    func process(_ sample: DeviceMotionSample, screen: DeviceMotionOrientation) -> DeviceMotionOutput {
        let axes = resolvedOrientation(screen)
        let upright = SIMD3<Float>(0, 1, 0)
        let correction: simd_quatf
        if let neutralUp {
            // The shortest rotation is ambiguous at 180 degrees.
            correction = neutralUp.y < -0.99999
                ? simd_quatf(angle: .pi, axis: SIMD3(0, 0, 1))
                : simd_quatf(from: neutralUp, to: upright)
        } else {
            correction = simd_quatf(angle: 0, axis: SIMD3(0, 0, 1))
        }

        let up = correction.act(axes.screenAxes(sample.up))
        let lateral = hypot(up.x, up.z)
        let angle = atan2(lateral, up.y)
        let gain = min(max(sensitivity, 0.5), 2)
        let deadZoneRadians = min(max(deadZone, 0), 15) * (.pi / 180)
        let tilt = min(max(0, angle - deadZoneRadians) * gain, Float.pi)
        var tunedUp = up
        if lateral > 0.0001 {
            let lateralScale = sin(tilt) / lateral
            tunedUp = SIMD3(up.x * lateralScale, cos(tilt), up.z * lateralScale)
        }

        var acceleration = tunedUp + correction.act(axes.screenAxes(sample.linearAcceleration))
        var rotation = correction.act(axes.screenAxes(sample.rotationRate)) * gain
        if invertSteering {
            // Reflection across the controller's vertical plane. Rotation is an axial vector.
            tunedUp.x = -tunedUp.x
            acceleration.x = -acceleration.x
            rotation.y = -rotation.y
            rotation.z = -rotation.z
        }
        return DeviceMotionOutput(up: tunedUp, accelerometer: acceleration, gyroscope: rotation)
    }
}
