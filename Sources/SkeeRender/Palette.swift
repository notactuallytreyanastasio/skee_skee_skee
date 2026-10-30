import CoreGraphics

public struct RGB: Hashable, Sendable {
    public var r, g, b: CGFloat
    public init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    init(r: CGFloat, g: CGFloat, b: CGFloat) { self.r = r; self.g = g; self.b = b }

    public func cg(_ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    public func mix(_ o: RGB, _ t: CGFloat) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }
    public func lighter(_ t: CGFloat) -> RGB { mix(RGB(0xFFFFFF), t) }
    public func darker(_ t: CGFloat) -> RGB { mix(RGB(0x000000), t) }
}

