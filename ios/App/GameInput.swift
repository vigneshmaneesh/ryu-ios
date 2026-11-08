import Combine
import GameController
import SwiftUI

@MainActor
final class GameInput: ObservableObject {
    @Published var controllerName = "Touch controls"
    private var timer: Timer?
    private var buttons: UInt64 = 0
    private var stick = SIMD2<Float>(0, 0)

    func start() {
        stop()
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publish() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        GCController.stopWirelessControllerDiscovery()
        buttons = 0; stick = .zero; ryu_input_reset()
    }
    func button(_ bit: Int, down: Bool) {
        if down { buttons |= UInt64(1) << bit } else { buttons &= ~(UInt64(1) << bit) }
        publish()
    }
    func leftStick(_ x: Float, _ y: Float) { stick = SIMD2(x, y); publish() }
    func releaseVirtual() { buttons = 0; stick = .zero; ryu_touch_set(0, 0, 0); publish() }
    private func publish() {
        var mask = buttons
        var left = stick, right = SIMD2<Float>(0, 0)
        let controller = GCController.controllers().first { $0.extendedGamepad != nil }
        let name = controller?.vendorName ?? "Touch controls"
        if name != controllerName { controllerName = name }
        if let pad = controller?.extendedGamepad {
            func press(_ bit: Int, _ down: Bool) { if down { mask |= UInt64(1) << bit } }
            // Match physical Switch positions: A right, B bottom, X top, Y left.
            press(0, pad.buttonB.isPressed); press(1, pad.buttonA.isPressed)
            press(2, pad.buttonY.isPressed); press(3, pad.buttonX.isPressed)
            press(4, pad.leftThumbstickButton?.isPressed == true); press(5, pad.rightThumbstickButton?.isPressed == true)
            press(6, pad.leftShoulder.isPressed); press(7, pad.rightShoulder.isPressed)
            press(8, pad.leftTrigger.isPressed); press(9, pad.rightTrigger.isPressed)
            press(10, pad.buttonMenu.isPressed); press(11, pad.buttonOptions?.isPressed == true)
            press(12, pad.dpad.left.isPressed); press(13, pad.dpad.up.isPressed)
            press(14, pad.dpad.right.isPressed); press(15, pad.dpad.down.isPressed)
            if left == .zero { left = SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value) }
            right = SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value)
        }
        func axis(_ value: Float) -> Int32 { Int32(max(-1, min(1, value)) * 32767) }
        ryu_input_set(mask, axis(left.x), axis(left.y), axis(right.x), axis(right.y))
    }
}

struct HeldButton: View {
    let title: String
    let bit: Int
    @ObservedObject var input: GameInput
    var size: CGFloat = 44
    @State private var held = false
    var body: some View {
        Text(title).font(.system(size: size < 40 ? 13 : 18, weight: .semibold, design: .rounded))
            .frame(width: size, height: size)
            .background(held ? Color.teal.opacity(0.85) : Color.white.opacity(0.16), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.3)))
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                if !held { held = true; input.button(bit, down: true) }
            }.onEnded { _ in held = false; input.button(bit, down: false) })
            .onDisappear { input.button(bit, down: false) }
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
    }
}

struct TouchStick: View {
    @ObservedObject var input: GameInput
    @State private var offset = CGSize.zero
    var body: some View {
        Circle().fill(.white.opacity(0.12)).frame(width: 104, height: 104)
            .overlay(Circle().fill(.white.opacity(0.35)).frame(width: 46, height: 46).offset(offset))
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let dx = value.location.x - 52, dy = value.location.y - 52
                let scale = max(1, hypot(dx, dy) / 35)
                offset = CGSize(width: dx / scale, height: dy / scale)
                input.leftStick(Float(offset.width / 35), Float(-offset.height / 35))
            }.onEnded { _ in offset = .zero; input.leftStick(0, 0) })
            .accessibilityLabel("Left analog stick")
    }
}
