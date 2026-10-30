import CoreGraphics
import SkeeCore

/// Four looks, two antes each. The run literally changes art style as you
/// climb: chunky pixels, then cel shading, then lit 3D, then neon vector.
public enum ArtStyle: String, CaseIterable, Hashable, Sendable, Codable {
    case pixel, cel, depth, neon

    public static func forAnte(_ ante: Int) -> ArtStyle {
        switch ante {
        case ...2: .pixel
        case 3...4: .cel
        case 5...6: .depth
        default: .neon
        }
    }

    public var title: String {
        switch self {
        case .pixel: "8-BIT ARCADE"
        case .cel: "CARTOON ALLEY"
        case .depth: "THE REAL DEAL"
        case .neon: "VECTOR NIGHT"
        }
    }
}

/// Where things go on screen. The Duo's hinge runs across the middle of the
/// inner display: the board is drawn above it, the lane below, so the ball
/// physically crosses the fold when it leaves the ramp.
public struct Layout: Hashable, Sendable {
    public let size: CGSize
    public var hingeY: CGFloat { size.height / 2 }
    public var hudHeight: CGFloat { 64 }
    public var trayHeight: CGFloat { 104 }

    public init(size: CGSize) { self.size = size }

    /// The target board region (top half, under the HUD).
    public var boardRect: CGRect {
        CGRect(x: 18, y: hudHeight, width: size.width - 36, height: hingeY - hudHeight)
    }

    /// The lane region (bottom half, above the tray of charms and balls).
    public var laneRect: CGRect {
        CGRect(x: 18, y: hingeY, width: size.width - 36, height: size.height - hingeY - trayHeight)
    }

    public var trayRect: CGRect {
        CGRect(x: 0, y: size.height - trayHeight, width: size.width, height: trayHeight)
    }
}

/// World (metres) to screen (points). Flat styles map the board with
/// separate x and y scales, which reads as a board seen at an angle.
/// The depth style uses a real perspective divide on both halves: the lane
/// recedes towards the hinge and the board recedes away from it, and they
/// share the same width at the fold.
public struct Projection: Sendable {
    public let layout: Layout
    public let style: ArtStyle
    let table: Table

    public init(layout: Layout, style: ArtStyle, table: Table = .standard) {
        self.layout = layout; self.style = style; self.table = table
    }

    var perspective: Bool { style == .depth }
    var halfBoard: Double { table.board.width / 2 }

    /// Width scale at the hinge in points per metre.
    var hingeScale: CGFloat {
        let full = layout.boardRect.width / CGFloat(table.board.width)
        return perspective ? full * 0.72 : full
    }

    /// Perspective factor along the board: 1 at the hinge, smaller away.
    func boardDepth(_ y: Double) -> CGFloat { perspective ? 1 / (1 + 0.55 * CGFloat(y)) : 1 }
    func laneDepth(_ s: Double) -> CGFloat {
        guard perspective else { return 1 }
        let fromNear = CGFloat(s / table.lane.length)  // 0 near the player, 1 at hinge
        // Near end is wider than the hinge: k(0) = 1.4, k(1) = 1.
        return 1.4 - 0.4 * fromNear
    }

    /// Screen point for a board position (z = 0).
    public func board(_ p: Vec2) -> CGPoint {
        let r = layout.boardRect
        let d = boardDepth(p.y)
        let x = r.midX + CGFloat(p.x) * hingeScale * d
        let yFrac: CGFloat
        if perspective {
            // Perspective-correct rise: maps y=0 -> 0, y=height -> 1.
            let h = CGFloat(table.board.height)
            yFrac = (CGFloat(p.y) * boardDepth(p.y)) / (h * boardDepth(table.board.height))
        } else {
            yFrac = CGFloat(p.y / table.board.height)
        }
        return CGPoint(x: x, y: r.maxY - yFrac * (r.height - 8))
    }

    /// Inverse of `board` for hit testing (flat styles; depth inverts
    /// numerically).
    public func boardPoint(at q: CGPoint) -> Vec2 {
        var lo = 0.0, hi = table.board.height
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if board(Vec2(0, mid)).y > q.y { lo = mid } else { hi = mid }
        }
        let y = (lo + hi) / 2
        let x = Double((q.x - layout.boardRect.midX) / (hingeScale * boardDepth(y)))
        return Vec2(x, y)
    }

    /// Screen point for a lane position; s = 0 at the release end.
    public func lane(x: Double, s: Double) -> CGPoint {
        let r = layout.laneRect
        let frac = CGFloat(s / table.lane.length)
        let yFrac: CGFloat = perspective ? 1 - pow(1 - frac, 1.35) : frac
        return CGPoint(x: r.midX + CGFloat(x) * hingeScale * laneDepth(s),
                       y: r.maxY - yFrac * r.height)
    }

    /// On-screen radius of the ball at a position, and how far above its
    /// shadow to draw it for height z.
    public func ballRadius(alongBoard y: Double?, s: Double?, z: Double) -> CGFloat {
        let base = CGFloat(table.board.ballRadius) * hingeScale * 0.62
        let d = y.map(boardDepth) ?? s.map(laneDepth) ?? 1
        return base * d * (1 + CGFloat(z) * 1.2)
    }

    public func lift(z: Double, alongBoard y: Double) -> CGFloat {
        CGFloat(z) * hingeScale * 0.9 * boardDepth(y)
    }

    /// Where a recorded path sample is on screen: ball centre and shadow.
    public func place(_ s: PathSample) -> (ball: CGPoint, shadow: CGPoint, radius: CGFloat) {
        let L = table.lane.length
        if s.along <= L {
            let p = lane(x: s.x, s: s.along)
            let r = ballRadius(alongBoard: nil, s: s.along, z: 0)
            return (CGPoint(x: p.x, y: p.y - r * 0.2), p, r)
        }
        let y = s.along - L
        let ground = board(Vec2(s.x, y))
        let r = ballRadius(alongBoard: y, s: nil, z: s.height)
        return (CGPoint(x: ground.x, y: ground.y - lift(z: s.height, alongBoard: y)), ground, r)
    }
}

/// A finished swipe on the lane, in screen points.
public struct Swipe: Sendable {
    public var start: CGPoint
    public var end: CGPoint
    /// Release velocity in points per second.
    public var velocity: CGVector

    public init(start: CGPoint, end: CGPoint, velocity: CGVector) {
        self.start = start; self.end = end; self.velocity = velocity
    }

    /// Speeds (pt/s, upward) at power 0 and power 1.
    public static let slowest: CGFloat = 400
    public static let fastest: CGFloat = 3400
    /// Swipe angle that maps to full aim.
    public static let fullAimRadians: CGFloat = 0.38

    /// nil if this was not an upward flick.
    public func launch(in layout: Layout, fold: Double) -> Launch? {
        let up = -velocity.dy
        guard up > 120 else { return nil }
        let power = (up - Self.slowest) / (Self.fastest - Self.slowest)
        let angle = atan2(velocity.dx, up)
        let half = layout.laneRect.width / 2
        let start = (start.x - layout.laneRect.midX) / half
        return Launch(power: Double(power), aim: Double(angle / Self.fullAimRadians),
                      start: Double(start), fold: fold)
    }
}
