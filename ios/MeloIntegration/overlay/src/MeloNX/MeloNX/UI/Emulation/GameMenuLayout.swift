import SwiftUI

struct GameViewportPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// Positions the host control in safe screen corners, preferring letterboxing.
struct GameMenuLayout {
    let revealRegion: CGRect
    let buttonFrame: CGRect

    var buttonCenter: CGPoint { CGPoint(x: buttonFrame.midX, y: buttonFrame.midY) }

    init(bounds: CGRect, safeInsets: EdgeInsets, viewport: CGRect, hasTouchControls: Bool) {
        let margin: CGFloat = 8
        let buttonSize: CGFloat = 44
        let left = bounds.minX + safeInsets.leading + margin
        let top = bounds.minY + safeInsets.top + margin
        let right = max(left, bounds.maxX - safeInsets.trailing - margin - buttonSize)
        let bottom = max(top, bounds.maxY - safeInsets.bottom - margin - buttonSize)

        // No full-screen or upper-half catch area: only the narrow top strip.
        revealRegion = CGRect(x: bounds.minX,
                              y: bounds.minY + safeInsets.top,
                              width: bounds.width, height: 32).intersection(bounds)

        let upperRight = CGRect(x: right, y: top, width: buttonSize, height: buttonSize)
        let upperLeft = CGRect(x: left, y: top, width: buttonSize, height: buttonSize)
        var candidates = [upperRight, upperLeft]
        // Avoid placing the host button over the virtual sticks/face buttons.
        if !hasTouchControls {
            candidates += [CGRect(x: right, y: bottom, width: buttonSize, height: buttonSize),
                           CGRect(x: left, y: bottom, width: buttonSize, height: buttonSize)]
        }
        let image = viewport.intersection(bounds)
        buttonFrame = candidates.first(where: { !$0.intersects(image) }) ?? upperRight
    }
}
