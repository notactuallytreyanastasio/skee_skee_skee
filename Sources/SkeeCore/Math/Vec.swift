/// Plain 2D vector. Used for positions and velocities in a plane
/// (lane plane or board plane). Value semantics, no hidden state.
public struct Vec2: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }

    public func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    public var length: Double { (x * x + y * y).squareRoot() }

    /// Unit vector in the same direction; the zero vector stays zero rather
    /// than becoming NaN.
    public var normalized: Vec2 {
        let l = length
        return l == 0 ? .zero : Vec2(x / l, y / l)
    }
}
