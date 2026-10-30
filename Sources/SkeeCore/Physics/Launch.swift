/// Everything the player controls about one ball, already normalised.
///
/// The shell turns a swipe (and the hinge angle) into a `Launch`; the core
/// never sees points, gestures or radians from UIKit.
public struct Launch: Hashable, Sendable, Codable {
    /// 0 = weakest roll the lane accepts, 1 = hardest.
    public let power: Double
    /// -1 = hard left, 1 = hard right, as a fraction of the lane's max angle.
    public let aim: Double
    /// Lateral release point: -1 = left rail, 1 = right rail.
    public let start: Double
    /// How far the device is folded: 0 = flat open, 1 = folded to the
    /// steepest ramp the game honours. Lofts the ball off the hinge.
    public let fold: Double
    /// Side spin from a thumb that curves as it lets go: -1 hooks left,
    /// 1 hooks right. The ball curves on the lane.
    public let spin: Double
    /// How jerky the stroke was, 0 smooth to 1 ragged. A jerky release
    /// skids the ball and costs speed, as a bad throw does.
    public let skid: Double

    public init(power: Double, aim: Double, start: Double = 0, fold: Double = 0, spin: Double = 0, skid: Double = 0) {
        self.power = clamp(power, 0, 1)
        self.aim = clamp(aim, -1, 1)
        self.start = clamp(start, -1, 1)
        self.fold = clamp(fold, 0, 1)
        self.spin = clamp(spin, -1, 1)
        self.skid = clamp(skid, 0, 1)
    }

    public var mirrored: Launch { Launch(power: power, aim: -aim, start: -start, fold: fold, spin: -spin, skid: skid) }
}
