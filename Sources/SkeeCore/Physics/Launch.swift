/// Everything the player controls about one ball, already normalised.
///
/// The shell turns a thumb stroke (and the hinge angle) into a `Launch`; the
/// core never sees points, gestures or radians from UIKit.
///
/// A thrown ball leaves the thumb at `from` metres up the lane moving at
/// `speed` m/s: exactly how it was moving under the thumb, so the throw
/// carries the velocity the player built up. Bots and the terminal think in
/// `power` instead, which is a speed released at the line.
public struct Launch: Hashable, Sendable, Codable {
    /// 0 = weakest roll the lane accepts, 1 = hardest, as a speed from the
    /// release line. For thumb throws this is derived from `speed` for display.
    public let power: Double
    /// Speed up the lane at the moment of release, m/s.
    public let speed: Double
    /// How far up the lane the ball was let go, metres.
    public let from: Double
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
        self.speed = LaneSpec.standard.releaseSpeed(power: self.power)
        self.from = 0
        self.aim = clamp(aim, -1, 1)
        self.start = clamp(start, -1, 1)
        self.fold = clamp(fold, 0, 1)
        self.spin = clamp(spin, -1, 1)
        self.skid = clamp(skid, 0, 1)
    }

    /// A throw let go mid-lane at a given speed.
    public init(speed: Double, from: Double, aim: Double, start: Double = 0, fold: Double = 0, spin: Double = 0, skid: Double = 0) {
        let lane = LaneSpec.standard
        self.speed = clamp(speed, 0, lane.maxSpeed * 1.3)
        self.from = clamp(from, 0, lane.length - 0.05)
        self.power = lane.power(forSpeed: self.speed)
        self.aim = clamp(aim, -1, 1)
        self.start = clamp(start, -1, 1)
        self.fold = clamp(fold, 0, 1)
        self.spin = clamp(spin, -1, 1)
        self.skid = clamp(skid, 0, 1)
    }

    enum CodingKeys: String, CodingKey { case power, speed, from, aim, start, fold, spin, skid }

    /// Saves from before thumb throws have no speed or release point: read
    /// them as a power from the line, so old runs still replay.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let power = try c.decode(Double.self, forKey: .power)
        let aim = try c.decode(Double.self, forKey: .aim)
        let start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        let fold = try c.decodeIfPresent(Double.self, forKey: .fold) ?? 0
        let spin = try c.decodeIfPresent(Double.self, forKey: .spin) ?? 0
        let skid = try c.decodeIfPresent(Double.self, forKey: .skid) ?? 0
        if let speed = try c.decodeIfPresent(Double.self, forKey: .speed) {
            self.init(speed: speed, from: try c.decodeIfPresent(Double.self, forKey: .from) ?? 0,
                      aim: aim, start: start, fold: fold, spin: spin, skid: skid)
        } else {
            self.init(power: power, aim: aim, start: start, fold: fold, spin: spin, skid: skid)
        }
    }

    public var mirrored: Launch {
        Launch(speed: speed, from: from, aim: -aim, start: -start, fold: fold, spin: -spin, skid: skid)
    }
}
