import Foundation
import CoreGraphics

public enum WindowPlacement {
    /// Keeps the entire window reachable, preferring the screen with the largest overlap.
    public static func clamp(_ proposed: CGRect, screens: [CGRect], fallback: CGRect) -> CGRect {
        let valid = screens.filter { !$0.isEmpty && !$0.isNull && $0.width.isFinite && $0.height.isFinite }
        let bounds = valid.max { lhs, rhs in
            let a = lhs.intersection(proposed), b = rhs.intersection(proposed)
            return (a.isNull ? 0 : a.width*a.height) < (b.isNull ? 0 : b.width*b.height)
        }.flatMap { $0.intersects(proposed) ? $0 : nil } ?? (valid.contains(fallback) ? fallback : valid.first ?? fallback)
        guard !bounds.isEmpty, !bounds.isNull else { return proposed }
        let width = min(max(proposed.width.isFinite ? proposed.width : 320, 98), bounds.width)
        let height = min(max(proposed.height.isFinite ? proposed.height : 240, 32), bounds.height)
        let x = proposed.minX.isFinite ? proposed.minX : bounds.minX
        let y = proposed.minY.isFinite ? proposed.minY : bounds.minY
        return CGRect(x: max(bounds.minX, min(x, bounds.maxX-width)), y: max(bounds.minY, min(y, bounds.maxY-height)), width: width, height: height)
    }
}
