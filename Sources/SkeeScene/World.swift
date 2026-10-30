import simd
import SkeeCore

/// Physics coordinates to scene coordinates. Pure. Metres, y up, the player
/// stands at +z looking down -z.
///
/// The lane rises at its physical incline. The board is drawn steeper than the
/// physics' 20 degrees so the rings face the player, the way a real target
/// stands up at the end of the alley; positions on it map one-to-one in
/// board coordinates, so the ball is always where the physics says.
public struct World: Sendable {
    public let table: Table
    public var boardTilt: Float = 50 * .pi / 180
    /// Height of the ridge at the hinge, for drawing only.
    public var humpHeight: Float = 0.035
    /// The lane is drawn shorter than it is: at full length the board ends
    /// up three metres from the camera and too small to read on a phone.
    /// Positions along the lane scale; the ball just looks a little slower.
    public var laneScale: Float = 0.42
    /// The target is drawn larger than it is, for the same reason. Every
    /// board position scales with it, so landings stay true.
    public var boardScale: Float = 1.55

    public init(table: Table = .standard) { self.table = table }

    var incline: Float { Float(table.lane.incline) }
    public var laneLength: Float { Float(table.lane.length) * laneScale }
    public var ballRadius: Float { Float(table.board.ballRadius) }

    public var laneNormal: SIMD3<Float> { SIMD3(0, cos(incline), sin(incline)) }
    public var laneForward: SIMD3<Float> { SIMD3(0, sin(incline), -cos(incline)) }

    /// Point on the lane surface.
    public func lane(x: Double, s: Double) -> SIMD3<Float> {
        SIMD3(Float(x), 0, 0) + laneForward * Float(s) * laneScale
    }

    public var boardOrigin: SIMD3<Float> { lane(x: 0, s: table.lane.length) + laneNormal * humpHeight }
    public var boardUp: SIMD3<Float> { SIMD3(0, sin(boardTilt), -cos(boardTilt)) }
    public var boardNormal: SIMD3<Float> { SIMD3(0, cos(boardTilt), sin(boardTilt)) }

    /// Point on (z = 0) or above the board.
    public func board(_ p: Vec2, z: Double = 0) -> SIMD3<Float> {
        boardOrigin + (SIMD3(Float(p.x), 0, 0) + boardUp * Float(p.y) + boardNormal * Float(z)) * boardScale
    }

    /// Drawn ball size at a sample: real size on the lane, growing to the
    /// board's scale over the first 15 cm past the ridge so the ball stays in
    /// proportion with the holes it drops into.
    public func ballScale(_ s: PathSample) -> Float {
        let past = Float(max(0, s.along - table.lane.length))
        return 1 + (boardScale - 1) * min(1, past / 0.15)
    }

    /// Ball centre for a recorded sample.
    public func ballCenter(_ s: PathSample) -> SIMD3<Float> {
        let L = table.lane.length
        if s.along <= L { return lane(x: s.x, s: s.along) + laneNormal * ballRadius }
        return board(Vec2(s.x, s.along - L), z: s.height) + boardNormal * ballRadius * ballScale(s)
    }

    /// The surface normal under a sample, for rolling.
    public func surfaceNormal(_ s: PathSample) -> SIMD3<Float> {
        s.along <= table.lane.length ? laneNormal : boardNormal
    }
}
