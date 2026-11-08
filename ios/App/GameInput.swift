import Combine
import GameController
import SwiftUI

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
    var right = false
    @State private var offset = CGSize.zero
    var body: some View {
        Circle().fill(.white.opacity(0.12)).frame(width: 104, height: 104)
            .overlay(Circle().fill(.white.opacity(0.35)).frame(width: 46, height: 46).offset(offset))
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let dx = value.location.x - 52, dy = value.location.y - 52
                let scale = max(1, hypot(dx, dy) / 35)
                offset = CGSize(width: dx / scale, height: dy / scale)
                if right { input.setRightStick(Float(offset.width / 35), Float(-offset.height / 35)) }
                else { input.leftStick(Float(offset.width / 35), Float(-offset.height / 35)) }
            }.onEnded { _ in offset = .zero; if right { input.setRightStick(0, 0) } else { input.leftStick(0, 0) } })
            .accessibilityLabel(right ? "Right analog stick" : "Left analog stick")
    }
}
