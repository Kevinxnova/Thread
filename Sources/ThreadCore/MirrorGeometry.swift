import Foundation

/// ScreenCaptureKit buffers and input use top-left coordinates; letterbox bars are never interactive.
public enum MirrorGeometry {
    public static func fittedRect(image: CGSize, in bounds: CGRect) -> CGRect? {
        guard image.width > 0, image.height > 0, bounds.width > 0, bounds.height > 0,
              [image.width, image.height, bounds.width, bounds.height].allSatisfy({ $0.isFinite }) else { return nil }
        let scale = min(bounds.width / image.width, bounds.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
    public static func sourcePoint(_ point: CGPoint, image: CGSize, in bounds: CGRect, source: CGRect) -> CGPoint? {
        guard let fit = fittedRect(image: image, in: bounds), fit.contains(point),
              source.width > 0, source.height > 0 else { return nil }
        return CGPoint(x: source.minX + (point.x - fit.minX) / fit.width * source.width,
                       y: source.minY + (point.y - fit.minY) / fit.height * source.height)
    }
}

/// Order is oldest to newest, independent of focus. Closing and reopening creates a new position.
public struct MirrorOrder: Equatable {
    public private(set) var ids: [UInt32] = []
    public init() {}
    public mutating func add(_ id: UInt32) { if !ids.contains(id) { ids.append(id) } }
    public mutating func remove(_ id: UInt32) { ids.removeAll { $0 == id } }
    public mutating func promote(_ id: UInt32) { remove(id); add(id) }
    public func rank(_ id: UInt32) -> Int? { ids.firstIndex(of: id) }
}
