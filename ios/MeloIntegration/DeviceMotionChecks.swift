import Foundation
import simd

@main
struct DeviceMotionChecks {
    private static let upright = SIMD3<Float>(0, 1, 0)

    static func main() throws {
        let defaults = DeviceMotionSettings()
        let holds: [(DeviceMotionOrientation, SIMD3<Float>)] = [
            (.portrait, upright),
            (.portLeft, SIMD3(-1, 0, 0)),
            (.portRight, SIMD3(1, 0, 0)),
            (.portraitUpsideDown, SIMD3(0, -1, 0)),
        ]
        for (screen, up) in holds {
            let output = defaults.process(sample(up), screen: screen)
            requireNear(output.accelerometer, upright, "An upright hold must centre on \(screen)")
            precondition(abs(output.rollDegrees) < 0.01)
        }

        // The same 30-degree steering gesture must agree in both landscape grips.
        let tilt: Float = .pi / 6
        let rightGrip = sample(SIMD3(cos(tilt), sin(tilt), 0))
        let leftGrip = sample(SIMD3(-cos(tilt), -sin(tilt), 0))
        let rightOutput = defaults.process(rightGrip, screen: .portRight)
        let leftOutput = defaults.process(leftGrip, screen: .portLeft)
        requireNear(leftOutput.accelerometer, rightOutput.accelerometer, "Landscape grips disagree")
        precondition(abs(rightOutput.rollDegrees - 27) < 0.01, "Right steering or the centre dead zone is incorrect")
        let smallTilt: Float = .pi / 90
        let centred = defaults.process(sample(SIMD3(cos(smallTilt), sin(smallTilt), 0)), screen: .portRight)
        requireNear(centred.accelerometer, upright, "Small movements inside the dead zone must centre")

        var settings = defaults
        settings.orientation = .portRight
        settings.recenter(sample(SIMD3(0.8, 0.2, 0.56)), screen: .portrait)
        let calibrated = settings.process(sample(SIMD3(0.8, 0.2, 0.56)), screen: .portLeft)
        requireNear(calibrated.accelerometer, upright, "A calibrated pitched hold failed to centre")

        settings.neutralUp = nil
        settings.invertSteering = true
        settings.sensitivity = 1.5
        let inverted = settings.process(rightGrip, screen: .portrait)
        precondition(abs(inverted.rollDegrees + 40.5) < 0.01, "Steering inversion or sensitivity is incorrect")
        let rotating = DeviceMotionSample(up: rightGrip.up, linearAcceleration: SIMD3(0, 0, 0.2),
                                          rotationRate: SIMD3(20, 0, 10))
        let rotated = settings.process(rotating, screen: .portrait)
        requireNear(rotated.gyroscope, SIMD3(0, -30, -15), "Angular-rate axes must use the same orientation and steering sign")
        precondition(abs(rotated.accelerometer.z - 0.2) < 0.01, "Preserve linear acceleration")

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DeviceMotionSettings.self, from: data)
        precondition(decoded == settings, "Saved gyro settings failed to round-trip")
        print("PASS device gyro upright and steering vectors for both landscape grips, recenter, dead zone, inversion and saved settings")
    }

    private static func sample(_ up: SIMD3<Float>) -> DeviceMotionSample {
        DeviceMotionSample(up: up, linearAcceleration: .zero, rotationRate: .zero)
    }

    private static func requireNear(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>, _ message: String) {
        precondition(simd_distance(actual, expected) < 0.01, message)
    }
}
