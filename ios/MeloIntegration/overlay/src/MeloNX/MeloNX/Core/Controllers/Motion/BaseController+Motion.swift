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
    private var listeners: [ObjectIdentifier: (DeviceMotionSample, DeviceMotionOrientation) -> Void] = [:]
    private var previews: Set<UUID> = []
    private var generation: UInt64 = 0
    private var sampling = false
    private var screen: DeviceMotionOrientation = .portrait
    private var latestSample: DeviceMotionSample?

    private init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
    }

    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return manager.isDeviceMotionAvailable
    }

    func updateScreenOrientation(_ orientation: UIInterfaceOrientation) {
        let newScreen: DeviceMotionOrientation
        switch orientation {
        case .landscapeLeft: newScreen = .portLeft
        case .landscapeRight: newScreen = .portRight
        case .portrait: newScreen = .portrait
        case .portraitUpsideDown: newScreen = .portraitUpsideDown
        default: return
        }
        lock.lock()
        screen = newScreen
        lock.unlock()
    }

    func subscribe(_ id: ObjectIdentifier, receive: @escaping (DeviceMotionSample, DeviceMotionOrientation) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        listeners[id] = receive
        updateSampling()
    }

    func unsubscribe(_ id: ObjectIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        listeners.removeValue(forKey: id)
        updateSampling()
    }

    func setPreviewActive(_ active: Bool, id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if active { previews.insert(id) }
        else { previews.remove(id) }
        updateSampling()
    }

    func snapshot() -> (DeviceMotionSample, DeviceMotionOrientation)? {
        lock.lock()
        defer { lock.unlock() }
        guard let latestSample else { return nil }
        return (latestSample, screen)
    }

    private func updateSampling() {
        let shouldSample = manager.isDeviceMotionAvailable && (!listeners.isEmpty || !previews.isEmpty)
        guard shouldSample != sampling else { return }
        sampling = shouldSample
        generation &+= 1
        if !shouldSample {
            latestSample = nil
            manager.stopDeviceMotionUpdates()
            return
        }
        let currentGeneration = generation
        manager.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let g = data.gravity
            let a = data.userAcceleration
            let r = data.rotationRate
            let sample = DeviceMotionSample(up: SIMD3(-Float(g.x), -Float(g.y), -Float(g.z)),
                                            linearAcceleration: SIMD3(-Float(a.x), -Float(a.y), -Float(a.z)),
                                            rotationRate: SIMD3(Float(r.x), Float(r.y), Float(r.z)) * (180 / .pi))
            self.lock.lock()
            guard self.generation == currentGeneration else {
                self.lock.unlock()
                return
            }
            self.latestSample = sample
            let callbacks = Array(self.listeners.values)
            let screen = self.screen
            self.lock.unlock()
            for callback in callbacks { callback(sample, screen) }
        }
    }
}

extension BaseController {
    func refreshMotion(_ source: ControllerMotionSource, deviceSettings: DeviceMotionSettings) {
        motionQueue.sync {
            guard motionAttached, isActive else { return }
            deviceMotionSettings = deviceSettings
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
            DeviceMotionFeed.shared.subscribe(ObjectIdentifier(self)) { [weak self] sample, screen in
                self?.motionQueue.async { [weak self] in
                    guard let self, self.isActive, self.motionGeneration == generation else { return }
                    let output = self.deviceMotionSettings.process(sample, screen: screen)
                    self.writeMotion(accelerometer: output.accelerometer, gyroscope: output.gyroscope)
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

}
