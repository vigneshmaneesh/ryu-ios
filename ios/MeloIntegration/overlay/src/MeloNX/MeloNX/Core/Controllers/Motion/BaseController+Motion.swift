// Motion input for physical and touch controllers.
import CoreMotion
import Foundation
import GameController
import UIKit

nonisolated enum ControllerMotionRoute {
    case controller
    case device
    case off
}

// Share one Core Motion stream when several controllers select device motion.
nonisolated final class DeviceMotionFeed {
    static let shared = DeviceMotionFeed()

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var listeners: [ObjectIdentifier: (CMDeviceMotion, UIDeviceOrientation) -> Void] = [:]
    private var generation: UInt64 = 0
    private var orientation: UIDeviceOrientation = .landscapeLeft

    private init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
    }

    @MainActor
    static func observeOrientation() {
        shared.updateOrientation(UIDevice.current.orientation)
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                shared.updateOrientation(UIDevice.current.orientation)
            }
        }
    }

    private func updateOrientation(_ orientation: UIDeviceOrientation) {
        guard orientation.isValidInterfaceOrientation else { return }
        lock.lock()
        self.orientation = orientation
        lock.unlock()
    }

    func subscribe(_ id: ObjectIdentifier, receive: @escaping (CMDeviceMotion, UIDeviceOrientation) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard manager.isDeviceMotionAvailable else { return }
        let shouldStart = listeners.isEmpty
        listeners[id] = receive
        guard shouldStart else { return }

        generation &+= 1
        let currentGeneration = generation
        manager.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.lock.lock()
            let callbacks = self.generation == currentGeneration ? Array(self.listeners.values) : []
            let orientation = self.orientation
            self.lock.unlock()
            for callback in callbacks { callback(data, orientation) }
        }
    }

    func unsubscribe(_ id: ObjectIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        if listeners.removeValue(forKey: id) != nil && listeners.isEmpty {
            generation &+= 1
            manager.stopDeviceMotionUpdates()
        }
    }
}

extension BaseController {
    func refreshMotion(_ source: ControllerMotionSource) {
        motionQueue.sync {
            guard motionAttached, isActive else { return }
            switch source {
            case .off:
                setMotionRoute(.off)
            case .device:
                setMotionRoute(.device)
            case .automatic:
                let hasControllerMotion = hasExternalMotionSensors || (nativeController?.motion != nil && !usesDeviceHandlers)
                setMotionRoute(hasControllerMotion ? .controller : .device)
            }
        }
    }

    func stopMotion() {
        motionQueue.sync {
            motionAttached = false
            setMotionRoute(.off)
        }
    }

    // Called only on motionQueue. Ignore callbacks already queued by an old source.
    private func setMotionRoute(_ route: ControllerMotionRoute) {
        if hasExternalMotionSensors {
            setExternalMotionSensorsActive(route == .controller)
        }
        guard route != motionRoute else { return }

        if motionRoute == .device {
            DeviceMotionFeed.shared.unsubscribe(ObjectIdentifier(self))
        } else if motionRoute == .controller && !hasExternalMotionSensors {
            nativeController?.motion?.valueChangedHandler = nil
            nativeController?.motion?.sensorsActive = false
        }
        if motionRoute != .off {
            writeMotion(accelerometer: .zero, gyroscope: .zero)
        }

        motionGeneration &+= 1
        let generation = motionGeneration
        motionRoute = route
        lastMotionSubmit = 0
        switch route {
        case .off:
            break
        case .controller:
            guard !hasExternalMotionSensors, let motion = nativeController?.motion else { return }
            motion.valueChangedHandler = { [weak self] motion in
                let acceleration = motion.acceleration
                let rotation = motion.rotationRate
                let accel = SIMD3(-Float(acceleration.x), -Float(acceleration.z), Float(acceleration.y))
                let gyro = SIMD3(Float(rotation.x), Float(rotation.z), -Float(rotation.y)) * (180 / .pi)
                self?.motionQueue.async { [weak self] in
                    guard let self, self.isActive, self.motionGeneration == generation else { return }
                    let now = DispatchTime.now().uptimeNanoseconds
                    guard now &- self.lastMotionSubmit >= 10_000_000 else { return }
                    self.lastMotionSubmit = now
                    self.writeMotion(accelerometer: accel, gyroscope: gyro)
                }
            }
            motion.sensorsActive = true
        case .device:
            DeviceMotionFeed.shared.subscribe(ObjectIdentifier(self)) { [weak self] motion, orientation in
                let gravity = motion.gravity
                let acceleration = motion.userAcceleration
                let rotation = motion.rotationRate
                let accel = SIMD3(-Float(gravity.x + acceleration.x), -Float(gravity.y + acceleration.y),
                                  -Float(gravity.z + acceleration.z))
                let gyro = SIMD3(Float(rotation.x), -Float(rotation.y), -Float(rotation.z)) * (180 / .pi)
                self?.motionQueue.async { [weak self] in
                    guard let self, self.isActive, self.motionGeneration == generation else { return }
                    let mappedAccel = self.remapDeviceMotion(accel, orientation: orientation)
                    let mappedGyro = self.remapDeviceMotion(gyro, orientation: orientation)
                    self.writeMotion(accelerometer: mappedAccel, gyroscope: mappedGyro)
                }
            }
        }
    }

    func submitExternalMotion(accelerometer: SIMD3<Float>?, gyroscope: SIMD3<Float>?) {
        motionQueue.async { [weak self] in
            guard let self, self.isActive, self.motionRoute == .controller else { return }
            self.writeMotion(accelerometer: accelerometer, gyroscope: gyroscope)
        }
    }

    private func writeMotion(accelerometer: SIMD3<Float>?, gyroscope: SIMD3<Float>?) {
        if let accelerometer {
            Ryujinx.setGamepadMotion(pointer, motionType: 1, axis: accelerometer)
        }
        if let gyroscope {
            Ryujinx.setGamepadMotion(pointer, motionType: 2, axis: gyroscope)
        }
    }

    private func remapDeviceMotion(_ value: SIMD3<Float>, orientation: UIDeviceOrientation) -> SIMD3<Float> {
        switch orientation {
        case .landscapeLeft: return SIMD3(value.y, -value.x, value.z)
        case .landscapeRight: return SIMD3(-value.y, value.x, value.z)
        case .portraitUpsideDown: return SIMD3(-value.x, value.z, value.y)
        default: return SIMD3(value.x, value.z, -value.y)
        }
    }
}
