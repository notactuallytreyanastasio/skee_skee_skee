/// Things that happened during a shot, in order. The shell turns these into
/// sound, haptics and juice; the scorer reads some of them (rattles count as
/// near misses).
public enum ShotEvent: Hashable, Sendable, Codable {
    /// Ball never cleared the hinge and rolled back.
    case dud
    case rail
    case launched
    case landed
    /// Ball came down on top of ring wall `ring` (0 = innermost) and bounced.
    case lip(ring: Int)
    case backwall
    case dropped(Hole)
    case settled(Hole)
    case gutter
}

public enum PathPhase: String, Hashable, Sendable, Codable {
    case lane, air, board
}

/// One recorded instant, for the shell to animate.
/// `along` is distance from the release point: 0...lane.length on the lane,
/// lane.length + y on the board. `height` is z above the board (0 on lane).
public struct PathSample: Hashable, Sendable, Codable {
    public var t: Double
    public var phase: PathPhase
    public var x: Double
    public var along: Double
    public var height: Double
}

public struct ShotResult: Hashable, Sendable, Codable {
    public var launch: Launch
    public var hole: Hole
    public var events: [ShotEvent]
    public var path: [PathSample]
    /// Speed along the lane at the ridge, nil for a dud.
    public var hingeSpeed: Double?
    public var firstLanding: Vec2?
    public var peakHeight: Double
    public var duration: Double

    /// How many lips the ball rattled on: the "near miss" count.
    public var rattles: Int {
        events.reduce(0) { n, e in if case .lip = e { n + 1 } else { n } }
    }
}
