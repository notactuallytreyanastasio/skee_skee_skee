/// The physical machine. Units are metres, seconds and radians, sized like a
/// real Skee-Ball alley so the tuning numbers mean something.
///
/// The ball rolls up the lane (bottom screen), leaves the hinge ridge at a
/// launch angle, and flies over a tilted target board (top screen) with
/// concentric ring walls. Coordinates on the board: x is lateral (0 = centre),
/// y runs up the board from the hinge (y = 0), z is height above the board.
public struct Table: Hashable, Sendable, Codable {
    public var lane: LaneSpec
    public var hinge: HingeSpec
    public var board: BoardSpec
    public var gravity: Double = 9.81
    /// Fixed integration step. Never derived from frame time: the shell
    /// replays recorded paths, it does not drive the simulation.
    public var dt: Double = 1.0 / 240.0
    public var maxDuration: Double = 8.0

    public static let standard = Table(lane: .standard, hinge: .standard, board: .standard)
}

public struct LaneSpec: Hashable, Sendable, Codable {
    public var length = 2.4
    public var width = 0.62
    public var incline = degrees(6)
    public var rollingFriction = 0.02
    public var railRestitution = 0.6
    /// Ball speed at power 0 and power 1.
    public var minSpeed = 2.0
    public var maxSpeed = 5.0
    /// Release angle at aim = ±1.
    public var maxAimAngle = degrees(8)

    public static let standard = LaneSpec()

    public func releaseSpeed(power: Double) -> Double {
        minSpeed + power * (maxSpeed - minSpeed)
    }
}

public struct HingeSpec: Hashable, Sendable, Codable {
    /// Launch angle above the board plane with the device flat open.
    public var baseAngle = degrees(45)
    /// Extra launch angle at fold = 1.
    public var foldGain = degrees(20)
    /// Fraction of the along-lane speed kept going over the ridge.
    public var carry = 1.0

    public static let standard = HingeSpec()

    public func launchAngle(fold: Double) -> Double { baseAngle + fold * foldGain }
}

public struct Pocket: Hashable, Sendable, Codable {
    public var hole: Hole
    public var center: Vec2
    public var radius: Double
}

public struct BoardSpec: Hashable, Sendable, Codable {
    public var width = 0.62
    /// The backwall sits at y = height.
    public var height = 1.0
    /// Tilt of the board relative to the flight frame; splits gravity into an
    /// in-plane pull down the board and a normal pull onto it.
    public var tilt = degrees(20)
    public var ringCenter = Vec2(0, 0.58)
    /// The 50 hole sits near the top of the 40 cup, not dead centre, so a ball
    /// that lands low in the cup rolls away from it instead of falling in.
    public var centerHoleOffset = Vec2(0, 0.03)
    public var centerHoleRadius = 0.04
    /// Balls moving faster than this in-plane skate over holes and pockets.
    public var captureSpeed = 1.2
    /// A ball must be falling at least this fast to bounce off a lip top;
    /// slower ones just meet the wall face. Stops balls skipping along lips.
    public var lipMinFall = 0.6
    /// Ring wall radii, smallest first. Inside wall 0 is the 40 cup, between
    /// 0 and 1 the 30, then 20, then 10. Outside the last wall is open board.
    public var ringWalls: [Double] = [0.10, 0.16, 0.22, 0.29]
    public var pockets: [Pocket] = [
        Pocket(hole: .pocketLeft, center: Vec2(-0.24, 0.90), radius: 0.05),
        Pocket(hole: .pocketRight, center: Vec2(0.24, 0.90), radius: 0.05),
    ]
    public var lipHeight = 0.025
    public var ballRadius = 0.03
    /// How far from a wall's centreline (as a fraction of ball radius) the
    /// ball's centre can be and still come down on the lip top.
    public var lipBand = 0.6
    /// Normal restitution when landing on the board face.
    public var bounce = 0.30
    /// Restitution off the top of a ring lip; the rattle.
    public var lipBounce = 0.3
    /// Sideways shove a lip gives, per m/s of incoming fall speed.
    public var lipKick = 0.2
    public var wallRestitution = 0.4
    public var backwallRestitution = 0.35
    public var rollingFriction = 0.08
    /// In-plane speed kept on each landing.
    public var landingGrip = 0.35
    /// Constant in-plane push (boss modifier); zero on a fair table.
    public var wind = Vec2.zero

    public static let standard = BoardSpec()

    public var centerHole: Vec2 { ringCenter + centerHoleOffset }

    /// Which ring zone a resting point is in, ignoring holes and pockets.
    public func zone(at p: Vec2) -> Hole {
        let d = (p - ringCenter).length
        for (i, r) in ringWalls.enumerated() where d < r { return Hole.byWallIndex[i] }
        return .gutter
    }
}
