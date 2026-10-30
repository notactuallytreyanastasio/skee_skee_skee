import CoreGraphics
import SkeeCore

/// One animated moment between two game states.
public enum Beat: Hashable, Sendable {
    /// The ball rolls along its recorded path.
    case roll(ShotResult, BallRecord)
    /// Every reel spins from the shown stops to these and settles.
    case spin(to: [Hole: Int])
    /// A frame's score is counted up step by step, Balatro style.
    case tally(FrameScore)
    /// Big centred text.
    case banner(String, sub: String, seconds: Double)
    /// Swap the shown state for the real one. Instant.
    case commit(RunState)
    /// Cross-fade the art style (ante changes).
    case restyle(from: ArtStyle, to: ArtStyle)

    public var duration: Double {
        switch self {
        case .roll(let r, _): r.path.last.map { $0.t * Presentation.rollSpeed } ?? 0
        case .spin: 0.75
        case .tally(let f): Double(f.steps.count) * 0.22 + 0.9
        case .banner(_, _, let s): s
        case .commit: 0
        case .restyle: 1.6
        }
    }
}

/// What the screen is showing, as opposed to what the game state is. The
/// reducer resolves a throw instantly; the presentation plays it out over a
/// few seconds and only then shows the new state. Pure value; the shell
/// calls `advance(dt)` each frame and `scene(...)` to draw.
public struct Presentation: Sendable {
    /// Slow motion factor applied to recorded shot time (1 = real time).
    public static let rollSpeed = 1.0

    public private(set) var shown: RunState
    public private(set) var beats: [Beat] = []
    public private(set) var beatTime = 0.0
    public private(set) var clock = 0.0
    /// Reel positions on screen. Fractional while spinning.
    public private(set) var reelPositions: [Hole: Double]
    var spinFrom: [Hole: Double] = [:]
    public private(set) var popups: [Popup] = []
    public private(set) var trail: [PathSample] = []
    public private(set) var flash = 0.0
    public private(set) var shake = 0.0
    /// The last ball's landing, kept on the board briefly.
    public private(set) var restingBall: (sample: PathSample, until: Double)?
    public private(set) var style: ArtStyle
    /// Power and result of recent throws, newest last: the lane gauge
    /// shows them so players can calibrate their flick.
    public private(set) var recentThrows: [ThrowMark] = []
    /// Points already counted up on screen but not yet in `shown`.
    public private(set) var talliedBonus = 0

    public init(state: RunState) {
        shown = state
        reelPositions = state.stops.mapValues(Double.init)
        style = ArtStyle.forAnte(state.ante)
    }

    public var isBusy: Bool { !beats.isEmpty }
    public var current: Beat? { beats.first }

    /// Turn a reducer step into beats. `step.state` is the truth; beats only
    /// decide how we get there on screen.
    /// - Parameter releaseAlong: how far up the lane the thumb let go. The
    ///   physics always starts a shot at the release line; the roll is
    ///   shown from where the ball actually left the thumb, so it doesn't
    ///   jump back.
    public mutating func enqueue(_ step: Step, releaseAlong: Double = 0) {
        var spun = false
        for event in step.events {
            switch event {
            case .fouled:
                beats.append(.banner("FOUL", sub: "thumb past the crease", seconds: 1.0))
            case .shot(let r, let b):
                beats.append(.roll(Self.trim(r, from: releaseAlong), b))
            case .frameScored(let f):
                beats.append(.tally(f))
            case .feverLit:
                beats.append(.spin(to: step.state.stops)); spun = true
                beats.append(.banner("FEVER", sub: "next frame x2", seconds: 1.2))
            case .roundCleared(let score, let target, let payout):
                if !spun { beats.append(.spin(to: step.state.stops)); spun = true }
                beats.append(.banner("CLEARED", sub: "\(score) / \(target)   +\(payout.total) TICKETS", seconds: 1.8))
            case .roundFailed(let score, let target):
                beats.append(.banner("GAME OVER", sub: "\(score) / \(target)", seconds: 2.4))
            case .runWon:
                beats.append(.banner("YOU BEAT THE ARCADE", sub: "", seconds: 3))
            case .anteStarted(let a, let boss):
                let from = style, to = ArtStyle.forAnte(a)
                if from != to { beats.append(.restyle(from: from, to: to)) }
                beats.append(.banner("ANTE \(a)", sub: "BOSS: \(boss.name.uppercased())", seconds: 1.6))
            case .roundStarted(let kind, let target):
                beats.append(.commit(step.state))
                beats.append(.banner(kind.title.uppercased(), sub: "REACH \(target)", seconds: 1.2))
            case .counterOpened, .bought, .sold, .rerolled, .armed:
                break
            }
        }
        if !spun && step.state.stops != shown.stops { beats.append(.spin(to: step.state.stops)) }
        beats.append(.commit(step.state))
    }

    /// Beats that finished during the last `advance`, for the shell's
    /// haptics and sound. Cleared at the start of each advance.
    public private(set) var finished: [Beat] = []

    public mutating func advance(_ dt: Double) {
        finished = []
        clock += dt
        flash = max(0, flash - dt * 2.5)
        shake = max(0, shake - dt * 3)
        popups = popups.compactMap { p in
            var q = p; q.age += dt / p.life; return q.age < 1 ? q : nil
        }
        if let r = restingBall, clock > r.until { restingBall = nil }
        var remaining = dt
        while let beat = beats.first {
            if beatTime == 0 { begin(beat) }
            let left = beat.duration - beatTime
            if remaining < left {
                beatTime += remaining
                during(beat)
                return
            }
            remaining -= max(left, 0)
            beatTime = beat.duration
            during(beat)
            finish(beat)
            finished.append(beat)
            beats.removeFirst()
            beatTime = 0
        }
    }

    /// Fast-forward everything queued.
    public mutating func skip() {
        while isBusy { advance(30) }
    }

    // MARK: beat lifecycle

    mutating func begin(_ beat: Beat) {
        switch beat {
        case .roll: trail = []
        case .spin:
            spinFrom = reelPositions
        case .tally(let f):
            if f.isJackpot { flash = 1; shake = 1 }
        case .banner: flash = max(flash, 0.4)
        case .commit, .restyle: break
        }
    }

    mutating func during(_ beat: Beat) {
        switch beat {
        case .roll(let r, _):
            let t = beatTime / Self.rollSpeed
            let sample = Self.sample(r.path, at: t)
            if let sample {
                trail.append(sample)
                if trail.count > 14 { trail.removeFirst(trail.count - 14) }
            }
        case .spin(let to):
            let u = min(1, beatTime / beat.duration)
            let eased = 1 - pow(1 - u, 3)
            for hole in BoardSetup.reelHoles {
                let n = Double(shown.setup.reel(hole).count)
                let start = spinFrom[hole] ?? 0
                var target = Double(to[hole] ?? 0)
                // Always spin forward at least two full turns plus the gap.
                while target < start + 2 * n { target += n }
                reelPositions[hole] = start + (target - start) * eased
            }
        case .tally, .banner, .commit, .restyle:
            break
        }
    }

    mutating func finish(_ beat: Beat) {
        switch beat {
        case .roll(let r, let b):
            if let last = r.path.last { restingBall = (last, clock + 0.6) }
            recentThrows.append(ThrowMark(power: r.launch.power, hole: b.hole))
            if recentThrows.count > 6 { recentThrows.removeFirst() }
            trail = []
            let text = b.hole == .gutter ? "GUTTER" : "+\(b.chips)"
            popups.append(Popup(text: text, anchor: .hole(b.hole), kind: b.hole == .gutter ? .bad : .chips))
            if r.rattles > 0 { shake = max(shake, 0.35) }
        case .spin(let to):
            reelPositions = to.mapValues(Double.init)
        case .tally(let f):
            let line: String
            switch f.payline {
            case .none: line = "\(f.total)"
            case .pair(let s): line = "PAIR OF \(s.rawValue.uppercased())S  \(f.total)"
            case .triple(let s): line = f.isJackpot ? "JACKPOT  \(f.total)" : "THREE \(s.rawValue.uppercased())S  \(f.total)"
            }
            popups.append(Popup(text: line, anchor: .center, kind: f.isJackpot ? .jackpot : .mult, life: 1.6))
            talliedBonus += f.total
        case .commit(let s):
            shown = s
            talliedBonus = 0
            reelPositions = s.stops.mapValues(Double.init)
        case .restyle(_, let to):
            style = to
        case .banner:
            break
        }
    }

    /// Drop the part of a path before it reaches `along`, re-timed to start
    /// at zero.
    static func trim(_ r: ShotResult, from along: Double) -> ShotResult {
        guard along > 0, let i = r.path.firstIndex(where: { $0.along >= along }), i > 0 else { return r }
        let t0 = r.path[i].t
        var out = r
        out.path = r.path[i...].map { s in var q = s; q.t -= t0; return q }
        return out
    }

    /// Linear interpolation into a recorded path.
    public static func sample(_ path: [PathSample], at t: Double) -> PathSample? {
        guard var prev = path.first else { return nil }
        for s in path.dropFirst() {
            if s.t >= t {
                let span = s.t - prev.t
                let u = span > 0 ? (t - prev.t) / span : 1
                func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * u }
                return PathSample(t: t, phase: u < 0.5 ? prev.phase : s.phase,
                                  x: mix(prev.x, s.x), along: mix(prev.along, s.along),
                                  height: mix(prev.height, s.height))
            }
            prev = s
        }
        return path.last
    }

    /// Where the ball is right now, if one is rolling.
    public var ball: PathSample? {
        if case .roll(let r, _) = beats.first { return Self.sample(r.path, at: beatTime / Self.rollSpeed) }
        return restingBall?.sample
    }

    /// Progress through a restyle, if one is running: (from, to, 0...1).
    public var restyleProgress: (ArtStyle, ArtStyle, Double)? {
        if case .restyle(let a, let b) = beats.first { return (a, b, beatTime / beats.first!.duration) }
        return nil
    }

    /// The frame being tallied and how many of its steps are revealed.
    public var tallyProgress: (FrameScore, Int)? {
        guard case .tally(let f) = beats.first else { return nil }
        return (f, min(f.steps.count, Int(beatTime / 0.22) + 1))
    }

    public var banner: (String, String, Double)? {
        guard case .banner(let a, let b, let s) = beats.first else { return nil }
        return (a, b, beatTime / s)
    }
}

public struct ThrowMark: Hashable, Sendable {
    public var power: Double
    public var hole: Hole
}

public struct Popup: Hashable, Sendable {
    public enum Anchor: Hashable, Sendable { case hole(Hole), center, hud }
    public enum Kind: Hashable, Sendable { case chips, mult, tickets, bad, jackpot }
    public var text: String
    public var anchor: Anchor
    public var kind: Kind
    public var life = 1.1
    public var age = 0.0
}
