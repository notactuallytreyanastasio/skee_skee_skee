/// The throw, as a pure function of a flick.
///
/// The ball waits at the release line. The player flicks up the lane the way
/// anyone flicks on a phone; after the thumb lifts, the shot fires from the
/// whole motion:
/// - speed: mostly the speed at lift-off, partly the peak, so a flick that
///   lets go at speed beats one that rides out to a stop,
/// - snap: accelerating through the release adds a little, easing off before
///   it costs a little,
/// - skid: jerk, normalised by the flick's own size and duration, against a
///   minimum-jerk reach (how people move when they move smoothly); a shaky
///   flick skids the ball and loses speed,
/// - aim: the speed-weighted direction near release,
/// - spin: sideways acceleration at release (a thumb that hooks),
/// - line: where across the lane the flick happened.
/// Touching well past the crease is a foul; flicks overshoot naturally, so the
/// give is generous.
public struct FlickSample: Hashable, Sendable, Codable {
    public var t: Double
    public var x: Double
    public var y: Double
    public init(t: Double, x: Double, y: Double) { self.t = t; self.x = x; self.y = y }
}

public struct FlickGeometry: Hashable, Sendable, Codable {
    public var creaseY: Double
    public var laneCenterX: Double
    public var laneHalfWidth: Double
    /// How far past the crease the thumb may go, still touching, before it is
    /// a foul.
    public var foulGive: Double

    public init(creaseY: Double, laneCenterX: Double, laneHalfWidth: Double, foulGive: Double = 140) {
        self.creaseY = creaseY; self.laneCenterX = laneCenterX; self.laneHalfWidth = laneHalfWidth; self.foulGive = foulGive
    }

    public var foulY: Double { creaseY - foulGive }
}

public enum StrokeOutcome: Hashable, Sendable {
    /// Not a throw: a tap, a pull backwards, a touch that started above the crease.
    case none
    case foul
    case release(Launch)
}

public struct FlickTuning: Hashable, Sendable, Codable {
    /// Effective flick speeds (pt/s) that map to power 0 and power 1.
    public var slowest = 300.0
    public var fastest = 3100.0
    /// Weight of lift-off speed against peak speed.
    public var releaseWeight = 0.5
    /// Snap: release acceleration, in units of peak speed per flick
    /// duration, that changes speed by `snapGain`.
    public var snapGain = 0.06
    /// Release angle off straight up (radians) for full aim.
    public var fullAimAngle = 0.35
    /// Sideways acceleration at release, in units of peak speed per flick
    /// duration, for full spin.
    public var fullSpin = 1.2
    /// Normalised jerk of a smooth flick, and how fast skid grows past it.
    public var smoothJerk = 7.0
    public var skidPerJerk = 0.1
    /// How much of a lane half-width the flick's horizontal position moves
    /// the release line.
    public var lineReach = 0.85

    public static let standard = FlickTuning()
}

/// What the analyser measured on the last flick it accepted, for the
/// tuning tool and on-screen feedback.
public struct FlickMetrics: Hashable, Sendable {
    public var peak, release, duration, jerk, snap, side, speed: Double
}
nonisolated(unsafe) public private(set) var lastMetrics: FlickMetrics?

public func crossedFoulLine(_ samples: [FlickSample], in g: FlickGeometry) -> Bool {
    samples.contains { $0.y < g.foulY }
}

public func analyzeFlick(_ samples: [FlickSample], in g: FlickGeometry, fold: Double = 0,
                         tuning k: FlickTuning = .standard) -> StrokeOutcome {
    guard let first = samples.first, first.y > g.creaseY else { return .none }
    if crossedFoulLine(samples, in: g) { return .foul }
    guard samples.count >= 4, let last = samples.last, first.y - last.y > 25 else { return .none }

    // Velocity, acceleration and jerk by differences, each lightly smoothed:
    // touch positions are quantised, and each difference amplifies noise.
    func diff(_ xs: [(t: Double, x: Double, y: Double)]) -> [(t: Double, x: Double, y: Double)] {
        zip(xs, xs.dropFirst()).compactMap { a, b in
            let dt = b.t - a.t
            return dt > 0 ? ((a.t + b.t) / 2, (b.x - a.x) / dt, (a.y - b.y) / dt) : nil
        }
    }
    func smooth(_ xs: [(t: Double, x: Double, y: Double)]) -> [(t: Double, x: Double, y: Double)] {
        xs.indices.map { i in
            let w = xs[max(0, i - 1)...min(xs.count - 1, i + 1)]
            let n = Double(w.count)
            return (xs[i].t, w.reduce(0) { $0 + $1.x } / n, w.reduce(0) { $0 + $1.y } / n)
        }
    }
    let pos = samples.map { (t: $0.t, x: $0.x, y: -$0.y) }   // y up
    let v = smooth(diff(pos.map { ($0.t, $0.x, -$0.y) }))      // y component = upward speed
    guard v.count >= 3 else { return .none }
    let a = smooth(diff(v.map { ($0.t, $0.x, -$0.y) }))
    let j = diff(a.map { ($0.t, $0.x, -$0.y) })

    let peak = v.map(\.y).max() ?? 0
    guard peak > 150 else { return .none }
    // The flick proper: from when it got going to lift-off.
    let startT = v.first { $0.y > peak * 0.08 }?.t ?? first.t
    let end = last.t
    let T = max(0.03, end - startT)

    // Lift-off speed: a line through the last few velocities, read at the end.
    let tail = v.filter { $0.t >= end - 0.06 }
    func atEnd(_ pick: ((t: Double, x: Double, y: Double)) -> Double) -> Double {
        guard tail.count >= 2 else { return pick(v.last!) }
        let n = Double(tail.count)
        let mt = tail.reduce(0) { $0 + $1.t } / n, mv = tail.reduce(0) { $0 + pick($1) } / n
        var num = 0.0, den = 0.0
        for e in tail { num += (e.t - mt) * (pick(e) - mv); den += (e.t - mt) * (e.t - mt) }
        return mv + (den > 0 ? num / den : 0) * (end - mt)
    }
    let release = max(0, atEnd { $0.y })
    guard release > 60 || peak > 600 else { return .none }

    let aTail = a.filter { $0.t >= end - 0.05 }
    let aUp = aTail.isEmpty ? 0 : aTail.reduce(0) { $0 + $1.y } / Double(aTail.count)
    let aSide = aTail.isEmpty ? 0 : aTail.reduce(0) { $0 + $1.x } / Double(aTail.count)
    let unitAccel = peak / T

    var speed = k.releaseWeight * release + (1 - k.releaseWeight) * peak
    speed *= 1 + k.snapGain * max(-1.5, min(1.5, aUp / unitAccel))

    // Normalised jerk: RMS jerk over the flick, in units of peak / T^2.
    let jf = j.filter { $0.t >= startT }
    let rms = jf.isEmpty ? 0 : (jf.reduce(0) { $0 + $1.y * $1.y + $1.x * $1.x } / Double(jf.count)).squareRoot()
    let jerk = rms * T * T / peak
    let skid = (jerk - k.smoothJerk) * k.skidPerJerk
    lastMetrics = FlickMetrics(peak: peak, release: release, duration: T, jerk: jerk,
                               snap: aUp / unitAccel, side: aSide / unitAccel, speed: speed)

    // Aim: speed-weighted direction over the last part of the flick.
    let dir = v.filter { $0.t >= end - 0.08 }
    let wx = dir.reduce(0) { $0 + $1.x * max(0, $1.y) }, wy = dir.reduce(0) { $0 + $1.y * max(0, $1.y) }
    let aim = _atan2(wx, max(wy, 1)) / k.fullAimAngle

    // The line: horizontal position where the flick was fastest.
    let fastest = v.max { $0.y < $1.y }!
    let xAt = samples.min { abs($0.t - fastest.t) < abs($1.t - fastest.t) }!.x
    let line = (xAt - g.laneCenterX) / g.laneHalfWidth * k.lineReach

    return .release(Launch(
        power: (speed - k.slowest) / (k.fastest - k.slowest),
        aim: aim, start: line, fold: fold,
        spin: aSide / unitAccel / k.fullSpin,
        skid: skid))
}

