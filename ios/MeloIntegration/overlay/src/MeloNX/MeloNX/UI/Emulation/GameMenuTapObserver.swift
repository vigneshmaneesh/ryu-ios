import SwiftUI
import UIKit

/// Observe the top-edge strip without placing a hit-testing surface over the game.
/// A window recognizer also sees touches delivered to the virtual controller.
struct GameMenuTapObserver: UIViewRepresentable {
    var revealRegion: CGRect
    var buttonRegion: CGRect
    var isButtonVisible: Bool
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> ObservationView {
        let view = ObservationView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        context.coordinator.update(revealRegion: revealRegion, buttonRegion: buttonRegion,
                                   isButtonVisible: isButtonVisible, onTap: onTap)
        return view
    }

    func updateUIView(_ view: ObservationView, context: Context) {
        context.coordinator.update(revealRegion: revealRegion, buttonRegion: buttonRegion,
                                   isButtonVisible: isButtonVisible, onTap: onTap)
        context.coordinator.attach(to: view)
    }

    static func dismantleUIView(_ view: ObservationView, coordinator: Coordinator) {
        coordinator.detach()
        view.coordinator = nil
    }

    final class ObservationView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void
        private var revealRegion: CGRect = .zero
        private var buttonRegion: CGRect = .zero
        private var isButtonVisible = false
        private weak var anchor: UIView?
        private weak var observedWindow: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        func update(revealRegion: CGRect, buttonRegion: CGRect, isButtonVisible: Bool,
                    onTap: @escaping () -> Void) {
            self.revealRegion = revealRegion
            self.buttonRegion = buttonRegion
            self.isButtonVisible = isButtonVisible
            self.onTap = onTap
        }

        func attach(to view: UIView) {
            anchor = view
            guard observedWindow !== view.window else { return }
            detach()
            anchor = view
            guard let window = view.window else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            recognizer = tap
            observedWindow = window
        }

        func detach() {
            if let recognizer {
                observedWindow?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            observedWindow = nil
            anchor = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            guard let anchor, let window = observedWindow,
                  anchor.window === window, !anchor.isHidden else { return false }
            let point = touch.location(in: anchor)
            guard anchor.bounds.contains(point) else { return false }
            return revealRegion.contains(point) || (isButtonVisible && buttonRegion.contains(point))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            onTap()
        }
    }
}
