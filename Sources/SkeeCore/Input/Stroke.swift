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
/// Everything is in screen points and seconds; the shell passes raw touches.
public struct TouchSample: Hashable, Sendable, Codable {
    public var t: Double
    public var x: Double
    public var y: Double
    public init(t: Double, x: Double, y: Double) { self.t = t; self.x = x; self.y = y }
}

/// Where the lane is on screen. y grows downward; the crease is the hinge.
public struct StrokeGeometry: Hashable, Sendable, Codable {
    public var creaseY: Double
    public var laneMinX: Double
    public var laneMaxX: Double
    public var bottomY: Double

    public init(creaseY: Double, laneMinX: Double, laneMaxX: Double, bottomY: Double) {
        self.creaseY = creaseY; self.laneMinX = laneMinX; self.laneMaxX = laneMaxX; self.bottomY = bottomY
    }
}

public enum StrokeOutcome: Hashable, Sendable {
    /// Not a throw: a tap, a pull backwards, a nudge.
    case none
    case foul
    case release(Launch)
}

public struct StrokeTuning: Hashable, Sendable, Codable {
    /// Upward release speeds (pt/s) that map to power 0 and power 1.
    public var slowest = 250.0
    public var fastest = 2600.0
    /// Release angle (radians off straight up) that maps to full aim.
    public var fullAimAngle = 0.35
    /// Change in sideways speed (pt/s) over the release that maps to full spin.
    public var fullSpin = 2200.0
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

public func crossedCrease(_ samples: [TouchSample], in g: StrokeGeometry) -> Bool {
    samples.contains { $0.y < g.creaseY }
}

public func analyzeStroke(_ samples: [TouchSample], in g: StrokeGeometry, fold: Double = 0,
                          tuning k: StrokeTuning = .standard) -> StrokeOutcome {
    if crossedCrease(samples, in: g) { return .foul }
    guard samples.count >= 3, let first = samples.first, let last = samples.last,
          first.y - last.y > 30 else { return .none }

    // Velocity between samples, then a 3-tap moving average: raw touch
    // positions are quantised and jittery.
    var raw: [(t: Double, vx: Double, up: Double)] = []
    for (a, b) in zip(samples, samples.dropFirst()) where b.t > a.t {
        let dt = b.t - a.t
        raw.append(((a.t + b.t) / 2, (b.x - a.x) / dt, (a.y - b.y) / dt))
    }
    guard raw.count >= 2 else { return .none }
    let v = raw.indices.map { i -> (t: Double, vx: Double, up: Double) in
        let w = raw[max(0, i - 1)...min(raw.count - 1, i + 1)]
        let n = Double(w.count)
        return (raw[i].t, w.reduce(0) { $0 + $1.vx } / n, w.reduce(0) { $0 + $1.up } / n)
    }

    let end = last.t
    func mean(_ from: Double, _ to: Double) -> (vx: Double, up: Double) {
        let w = v.filter { $0.t >= from && $0.t <= to }
        let use = w.isEmpty ? [v.last!] : w
        let n = Double(use.count)
        return (use.reduce(0) { $0 + $1.vx } / n, use.reduce(0) { $0 + $1.up } / n)
    }
    let release = mean(end - k.releaseWindow, end)
    guard release.up > 150 else { return .none }

    // Spin: how much the sideways speed changed going into the release.
    let before = mean(end - 3 * k.releaseWindow, end - k.releaseWindow)
    let spin = (release.vx - before.vx) / k.fullSpin

    // Skid: total speed lost to decelerations over the stroke, relative to
    // its peak. A good throw only speeds up.
    let stroke = v.filter { $0.t >= end - k.strokeWindow }
    let peak = stroke.map(\.up).max() ?? release.up
    var lost = 0.0
    for (a, b) in zip(stroke, stroke.dropFirst()) where b.up < a.up { lost += a.up - b.up }
    let hitch = peak > 0 ? lost / peak : 0
    let skid = (hitch - k.hitchAllowance) * k.skidGain

    let half = (g.laneMaxX - g.laneMinX) / 2
    let mid = (g.laneMaxX + g.laneMinX) / 2
    return .release(Launch(
        power: (release.up - k.slowest) / (k.fastest - k.slowest),
        aim: atan2Safe(release.vx, release.up) / k.fullAimAngle,
        start: (last.x - mid) / half,
        fold: fold,
        spin: spin,
        skid: skid))
}

private func atan2Safe(_ y: Double, _ x: Double) -> Double { _atan2(y, x) }
