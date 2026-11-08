import Foundation
import GameController
import CoreMotion
import CoreHaptics
import SwiftUI
import simd

@MainActor final class GameInput: ObservableObject {
    @Published var controllerName = "Touch controls"
    @Published var showTouch = true
    @Published var touchOpacity = 0.7
    @Published var touchScale = 1.0
    private var timer: Timer?
    private var buttons: UInt64 = 0
    private var stick = SIMD2<Float>.zero
    private var rightStick = SIMD2<Float>.zero
    private var configuration = InputConfiguration.defaults()
    private let motionManager = CMMotionManager()
    private var rotations = Array(repeating: SIMD3<Double>.zero, count: 8)
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var haptics: [Int: ControllerHaptics] = [:]
    private var mouse: GCMouse?
    private var mousePoint = SIMD2<Float>(640, 360)
    private var wheel = SIMD2<Float>.zero
    private var suspended = false

    func start(program: URL? = nil) {
        stop()
        do { configuration = try InputSettingsStore.effective(program) }
        catch { controllerName = "Input settings could not be read: " + error.localizedDescription; return }
        touchOpacity = configuration.touchOpacity; touchScale = configuration.touchScale
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        if configuration.profiles.contains(where: { $0.motion == "device" }), motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1 / configuration.pollRate
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        }
        lastTime = ProcessInfo.processInfo.systemUptime
        suspended = false
        timer = Timer(timeInterval: 1 / configuration.pollRate, repeats: true) { [weak self] _ in Task { @MainActor in self?.publish() } }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        publish()
    }
    func stop() {
        timer?.invalidate(); timer = nil
        motionManager.stopDeviceMotionUpdates()
        GCController.stopWirelessControllerDiscovery()
        for output in haptics.values { output.stop() }; haptics.removeAll()
        mouse?.mouseInput?.mouseMovedHandler = nil; mouse = nil
        buttons = 0; stick = .zero; rightStick = .zero; rotations = Array(repeating: .zero, count: 8)
        ryu_input_reset()
    }
    func button(_ bit: Int, down: Bool) { if down { buttons |= UInt64(1) << bit } else { buttons &= ~(UInt64(1) << bit) }; publish() }
    func leftStick(_ x: Float, _ y: Float) { stick = SIMD2(x, y); publish() }
    func setRightStick(_ x: Float, _ y: Float) { rightStick = SIMD2(x, y); publish() }
    func setPaused(_ paused: Bool) {
        suspended = paused
        if paused { for output in haptics.values { output.stop() }; haptics.removeAll() }
        else { lastTime = ProcessInfo.processInfo.systemUptime }
    }
    func releaseVirtual() {
        buttons = 0; stick = .zero; rightStick = .zero
        for finger in 0..<16 { ryu_touch_finger(Int32(finger), 0, 0, 0) }
        publish()
    }
    private func publish() {
        guard !suspended else { return }
        let now = ProcessInfo.processInfo.systemUptime, delta = min(0.05, max(0, now - lastTime)); lastTime = now
        let controllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        var used: Set<Int> = []
        let names = controllers.compactMap(\.vendorName).joined(separator: ", ")
        if names.isEmpty && controllerName != "Touch controls" { controllerName = "Touch controls" }
        else if !names.isEmpty && names != controllerName { controllerName = names }
        showTouch = !configuration.hideTouchWithController || controllers.isEmpty
        let keyboard = GCKeyboard.coalesced?.keyboardInput
        var keys = [UInt64](repeating: 0, count: 4), modifiers: Int32 = 0
        var down: Set<Int> = []
        if let keyboard {
            for code in 0..<256 where keyboard.button(forKeyCode: GCKeyCode(rawValue: code))?.isPressed == true { down.insert(code); keys[code / 64] |= UInt64(1) << (code % 64) }
            if down.contains(224) || down.contains(228) { modifiers |= 1 }
            if down.contains(225) || down.contains(229) { modifiers |= 2 }
            if down.contains(226) { modifiers |= 4 }; if down.contains(230) { modifiers |= 8 }
            if down.contains(227) || down.contains(231) { modifiers |= 16 }
        }
        ryu_keyboard_set(keys[0], keys[1], keys[2], keys[3], modifiers)
        for player in 0..<8 {
            guard let id = configuration.assignments[player], let profile = configuration.profiles.first(where: { $0.id == id }) else {
                ryu_input_player(Int32(player), 0, 1, 0, 0, 0, 0, 0); continue
            }
            let index = profile.device
            var controller: GCController?
            if controllers.indices.contains(index) && (configuration.allowDuplicateDeviceAssignment || !used.contains(index)) { controller = controllers[index]; used.insert(index) }
            var mask: UInt64 = player == 0 ? buttons : 0
            var left = player == 0 ? stick : .zero, right = player == 0 ? rightStick : .zero
            if let pad = controller?.extendedGamepad {
                let sources: [String: Bool] = ["A":pad.buttonA.isPressed, "B":pad.buttonB.isPressed, "X":pad.buttonX.isPressed, "Y":pad.buttonY.isPressed,
                    "LS":pad.leftThumbstickButton?.isPressed == true, "RS":pad.rightThumbstickButton?.isPressed == true, "L":pad.leftShoulder.isPressed, "R":pad.rightShoulder.isPressed,
                    "ZL":pad.leftTrigger.isPressed, "ZR":pad.rightTrigger.isPressed, "Plus":pad.buttonMenu.isPressed, "Minus":pad.buttonOptions?.isPressed == true,
                    "Left":pad.dpad.left.isPressed, "Up":pad.dpad.up.isPressed, "Right":pad.dpad.right.isPressed, "Down":pad.dpad.down.isPressed]
                for bit in 0..<16 where sources[profile.mapping[String(bit)] ?? "Unbound"] == true { mask |= UInt64(1) << bit }
                if left == .zero { left = SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value) }
                if right == .zero { right = SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value) }
            }
            if profile.keyboard {
                for bit in 0..<16 { if let code = profile.keyboardMapping[String(bit)], code > 0 && down.contains(code) { mask |= UInt64(1) << bit } }
                func held(_ code: Int) -> Float { down.contains(code) ? 1 : 0 }
                if left == .zero { left = SIMD2(held(7) - held(4), held(26) - held(22)) }
                if right == .zero { right = SIMD2(held(15) - held(13), held(12) - held(14)) }
            }
            if profile.swapSticks { swap(&left, &right) }
            func axis(_ value: SIMD2<Float>, invertX: Bool, invertY: Bool) -> SIMD2<Float> {
                let length = simd_length(value), deadzone = min(0.9, max(0, profile.deadzone))
                guard length > deadzone else { return .zero }
                let scale = min(1, (length - deadzone) / (1 - deadzone) * max(0.1, profile.range)) / length
                return value * scale * SIMD2(invertX ? -1 : 1, invertY ? -1 : 1)
            }
            left = axis(left, invertX: profile.invertLeftX, invertY: profile.invertLeftY); right = axis(right, invertX: profile.invertRightX, invertY: profile.invertRightY)
            func raw(_ value: Float) -> Int32 { Int32(max(-1, min(1, value)) * 32767) }
            ryu_input_player(Int32(player), 1, profile.type, mask, raw(left.x), raw(left.y), raw(right.x), raw(right.y))
            publishMotion(player, profile, controller, delta)
            var rumble = [Float](repeating: 0, count: 8); rumble.withUnsafeMutableBufferPointer { ryu_rumble_read(Int32(player), $0.baseAddress) }
            if profile.rumble {
                let intensity = min(1, ([rumble[0], rumble[2], rumble[4], rumble[6]].max() ?? 0) * profile.rumbleStrength)
                if intensity > 0 && haptics[player] == nil { haptics[player] = ControllerHaptics(controller: controller, allowDevice: player == 0) }
                haptics[player]?.update(intensity, sharpness: min(1, max(rumble[2], rumble[6])))
            }
        }
        publishMouse()
    }
    private func publishMotion(_ player: Int, _ profile: ControllerProfile, _ controller: GCController?, _ delta: Double) {
        var acceleration = SIMD3<Double>(0, 0, -1), gyro = SIMD3<Double>.zero
        var attitude = simd_quatf(angle: 0, axis: SIMD3(0, 0, 1))
        if profile.motion == "device", let motion = motionManager.deviceMotion {
            acceleration = SIMD3(motion.gravity.x + motion.userAcceleration.x, motion.gravity.y + motion.userAcceleration.y, motion.gravity.z + motion.userAcceleration.z)
            gyro = SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z)
            let q = motion.attitude.quaternion; attitude = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
        } else if profile.motion == "controller", let motion = controller?.motion {
            motion.sensorsActive = true
            let a = motion.acceleration, g = motion.rotationRate, q = motion.attitude
            acceleration = SIMD3(a.x, a.y, a.z); gyro = SIMD3(g.x, g.y, g.z)
            attitude = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
        } else { return }
        if simd_length(gyro) < Double(profile.motionDeadzone) { gyro = .zero }
        gyro *= Double(profile.motionSensitivity) / 100
        rotations[player] += gyro * delta
        let factor = 180 / Double.pi * 0.0027 // Same gyro/rotation scaling as the upstream input adapter.
        let angular = gyro * factor, rotation = rotations[player] * factor
        let matrix = simd_float3x3(simd_length(attitude.vector) > 0.5 ? simd_normalize(attitude) : simd_quatf(angle: 0, axis: SIMD3(0, 0, 1)))
        var values: [Float] = [Float(-acceleration.x), Float(-acceleration.y), Float(-acceleration.z), Float(angular.x), Float(angular.y), Float(angular.z), Float(rotation.x), Float(rotation.y), Float(rotation.z)]
        for column in 0..<3 { for row in 0..<3 { values.append(matrix[column][row]) } }
        values.withUnsafeBufferPointer { ryu_motion_set(Int32(player), $0.baseAddress) }
    }
    private func publishMouse() {
        if mouse !== GCMouse.current {
            mouse?.mouseInput?.mouseMovedHandler = nil; mouse = GCMouse.current
            mouse?.mouseInput?.mouseMovedHandler = { [weak self] _, dx, dy in Task { @MainActor in
                guard let self else { return }; self.mousePoint += SIMD2(dx, -dy); self.mousePoint = simd_clamp(self.mousePoint, .zero, SIMD2(1279, 719))
            } }
            mouse?.mouseInput?.scroll.xAxis.valueChangedHandler = { [weak self] _, value in Task { @MainActor in self?.wheel.x += value } }
            mouse?.mouseInput?.scroll.yAxis.valueChangedHandler = { [weak self] _, value in Task { @MainActor in self?.wheel.y += value } }
        }
        var buttons: UInt32 = 0
        if let input = mouse?.mouseInput { if input.leftButton.isPressed { buttons |= 1 }; if input.rightButton?.isPressed == true { buttons |= 2 }; if input.middleButton?.isPressed == true { buttons |= 4 } }
        ryu_mouse_set(Int32(mousePoint.x), Int32(mousePoint.y), buttons, Int32(wheel.x), Int32(wheel.y), mouse == nil ? 0 : 1); wheel = .zero
    }
}

@MainActor private final class ControllerHaptics {
    private let engine: CHHapticEngine
    private let player: CHHapticAdvancedPatternPlayer
    private var last: Float = -1
    init?(controller: GCController?, allowDevice: Bool) {
        do {
            if let controller {
                guard let engine = controller.haptics?.createEngine(withLocality: .default) else { return nil }; self.engine = engine
            } else {
                guard allowDevice, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }; engine = try CHHapticEngine(); engine.playsHapticsOnly = true
            }
            try engine.start()
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [.init(parameterID: .hapticIntensity, value: 0), .init(parameterID: .hapticSharpness, value: 0.5)], relativeTime: 0, duration: 10)
            player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: [])); player.loopEnabled = true; player.loopEnd = 10; try player.start(atTime: CHHapticTimeImmediate)
        } catch { return nil }
    }
    func update(_ intensity: Float, sharpness: Float) {
        guard abs(last - intensity) > 0.01 else { return }; last = intensity
        try? player.sendParameters([.init(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0), .init(parameterID: .hapticSharpnessControl, value: sharpness, relativeTime: 0)], atTime: CHHapticTimeImmediate)
    }
    func stop() { try? player.stop(atTime: CHHapticTimeImmediate); engine.stop(completionHandler: nil) }
}
