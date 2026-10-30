/// The thumb throw, as a pure function of touch samples.
///
/// The ball sits under the thumb. The player slides it up the lane and lets
/// go before the crease, the way a skee-ball leaves your hand at the foul
/// line. The release velocity sets power and aim; the shape of the stroke
/// matters too:
/// - a thumb that curves as it lets go puts side spin on the ball,
/// - a stroke that speeds up and slows down (hitches) skids the ball,
/// - any touch past the crease is a foul.
///
/// Each sample has the thumb on the glass (points) and the ball on the lane
/// (metres, through the camera). Speed comes from the glass: the lane is in
/// perspective, so a point of travel is 3 mm of lane at the bottom of the
/// screen and 14 mm at the crease, and a throw measured in lane metres would
/// be four times harder near the crease for the same thumb. What a player
/// feels is their thumb's speed, so that is what carries into the throw.
/// The release point comes from the lane: where the ball actually was.
public struct StrokeSample: Hashable, Sendable, Codable {
    public var t: Double
    /// Thumb on the glass, points (y grows downward).
    public var screenX: Double
    public var screenY: Double
    /// Ball on the lane: x across (0 = centre), s up the lane, metres.
    public var x: Double
    public var s: Double
    public init(t: Double, screenX: Double, screenY: Double, x: Double, s: Double) {
        self.t = t; self.screenX = screenX; self.screenY = screenY; self.x = x; self.s = s
    }
}

public struct StrokeGeometry: Hashable, Sendable, Codable {
    public var creaseY: Double
    public var laneHalfWidth: Double
    /// How far past the crease the thumb may sink before it's a foul. The
    /// fold is a dip, and a thumb letting go rides down into it; that should
    /// feel like the release, not get punished.
    public var foulGive: Double

    public init(creaseY: Double, laneHalfWidth: Double, foulGive: Double = 40) {
        self.creaseY = creaseY; self.laneHalfWidth = laneHalfWidth; self.foulGive = foulGive
    }

    /// Touches above this screen line are fouls.
    public var foulY: Double { creaseY - foulGive }
}

public enum StrokeOutcome: Hashable, Sendable {
    /// Not a throw: a tap, a pull backwards, a nudge.
    case none
    case foul
    case release(Launch)
}

public struct StrokeTuning: Hashable, Sendable, Codable {
    /// Lane metres per point of thumb travel: thrown speed = thumb speed on
    /// the glass times this. 700-950 pt/s covers the scoring range.
    public var metersPerPoint = 0.0036
    /// Release angle off straight up (radians) that maps to full aim.
    public var fullAimAngle = 0.35
    /// Change in sideways thumb speed (pt/s) over the release that maps to
    /// full spin.
    public var fullSpin = 900.0
    /// Speed lost to hitches, as a fraction of peak, that is free; beyond it
    /// skid grows at `skidGain` per unit.
    public var hitchAllowance = 0.1
    public var skidGain = 1.2
    /// The window at the end of the stroke that defines the release.
    public var releaseWindow = 0.05
    /// The window over which hitches are counted.
    public var strokeWindow = 0.25

    public static let standard = StrokeTuning()
}

public func crossedCrease(_ samples: [StrokeSample], in g: StrokeGeometry) -> Bool {
    samples.contains { $0.screenY < g.foulY }
}

public func analyzeStroke(_ samples: [StrokeSample], in g: StrokeGeometry, fold: Double = 0,
                          tuning k: StrokeTuning = .standard) -> StrokeOutcome {
    if crossedCrease(samples, in: g) { return .foul }
    guard samples.count >= 3, let first = samples.first, let last = samples.last,
          first.screenY - last.screenY > 25 else { return .none }

    // Velocity between samples, then a 3-tap moving average: raw touch
    // positions are quantised and jittery.
    var raw: [(t: Double, vx: Double, vs: Double)] = []
    for (a, b) in zip(samples, samples.dropFirst()) where b.t > a.t {
        let dt = b.t - a.t
        // Upward is positive: screen y decreases as the thumb goes up.
        raw.append(((a.t + b.t) / 2, (b.screenX - a.screenX) / dt, (a.screenY - b.screenY) / dt))
    }
    guard raw.count >= 2 else { return .none }
    let v = raw.indices.map { i -> (t: Double, vx: Double, vs: Double) in
        let w = raw[max(0, i - 1)...min(raw.count - 1, i + 1)]
        let n = Double(w.count)
        return (raw[i].t, w.reduce(0) { $0 + $1.vx } / n, w.reduce(0) { $0 + $1.vs } / n)
    }

    let end = last.t
    func mean(_ from: Double, _ to: Double) -> (vx: Double, vs: Double) {
        let w = v.filter { $0.t >= from && $0.t <= to }
        let use = w.isEmpty ? [v.last!] : w
        let n = Double(use.count)
        return (use.reduce(0) { $0 + $1.vx } / n, use.reduce(0) { $0 + $1.vs } / n)
    }
    // Speed at the instant of letting go: a line through the last stretch of
    // velocities, read at the end. A plain average lags a thumb that is
    // still speeding up, and the throw would lose what it built.
    func atRelease(_ pick: ((t: Double, vx: Double, vs: Double)) -> Double) -> Double {
        let w = v.filter { $0.t >= end - 1.6 * k.releaseWindow }
        guard w.count >= 2 else { return pick(v.last!) }
        let n = Double(w.count)
        let mt = w.reduce(0) { $0 + $1.t } / n, mv = w.reduce(0) { $0 + pick($1) } / n
        var num = 0.0, den = 0.0
        for e in w { num += (e.t - mt) * (pick(e) - mv); den += (e.t - mt) * (e.t - mt) }
        return mv + (den > 0 ? num / den : 0) * (end - mt)
    }
    let release = (vx: atRelease { $0.vx }, vs: atRelease { $0.vs })
    guard release.vs > 80 else { return .none }

    let before = mean(end - 3 * k.releaseWindow, end - k.releaseWindow)
    let spin = (release.vx - before.vx) / k.fullSpin

    let stroke = v.filter { $0.t >= end - k.strokeWindow }
    let peak = stroke.map(\.vs).max() ?? release.vs
    var lost = 0.0
    for (a, b) in zip(stroke, stroke.dropFirst()) where b.vs < a.vs { lost += a.vs - b.vs }
    let hitch = peak > 0 ? lost / peak : 0

    return .release(Launch(
        speed: release.vs * k.metersPerPoint,
        from: last.s,
        aim: _atan2(release.vx, release.vs) / k.fullAimAngle,
        start: last.x / g.laneHalfWidth,
        fold: fold,
        spin: spin,
        skid: (hitch - k.hitchAllowance) * k.skidGain))
}
