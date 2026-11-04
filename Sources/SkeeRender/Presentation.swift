import CoreGraphics
import SkeeCore

/// One animated moment between two game states.
public enum Beat: Hashable, Sendable {
    /// The ball rolls along its recorded path.
    case roll(ShotResult, BallRecord)
    /// Every reel, the board's and the top slot's, spins from the shown
    /// stops to these and settles.
    case spin(to: [Hole: Int])
    /// The lever: the machine's reels spin to the pull and stop left to
    /// right, then hold so the wins can be read.
    case pull(Pull)
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
        case .pull(let p): Presentation.pullDuration(p)
        case .tally(let f): Double(f.steps.count) * Presentation.tallyStep + 0.6
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
    /// How many seconds of screen time each recorded second of a shot takes
    /// (1 = real time). At real time the whole throw was over in 1.2 s and
    /// read as a flick of light, not a heavy ball rolling up an alley; 1.4
    /// gives the roll a second to watch and the hop its hang time.
    public static let rollSpeed = 1.4
    /// Seconds per revealed tally step.
    public static let tallyStep = 0.15
    /// How slow time runs while a line-completing ball is in the air.
    public static let anticipationScale = 0.4

    public private(set) var shown: RunState
    public private(set) var beats: [Beat] = []
    public private(set) var beatTime = 0.0
    public private(set) var clock = 0.0
    /// Reel positions on screen. Fractional while spinning.
    public private(set) var reelPositions: [Hole: Double]
    var spinFrom: [Hole: Double] = [:]
    /// The top slot's three reels on screen, as positions on `TopSlot.strip`.
    /// The pull machine's three reels on screen, as positions on
    /// `Pull.strips`; the top visible row. Fractional while spinning.
    public private(set) var pullPositions: [Double]
    var pullFrom: [Double] = []
    var pullStopped = 0
    /// The pull on show, once its reels have stopped.
    public private(set) var lastPull: Pull?
    public private(set) var popups: [Popup] = []
    public private(set) var trail: [PathSample] = []
    public private(set) var flash = 0.0
    public private(set) var shake = 0.0
    /// A coin shower in progress, 1 down to 0.
    public private(set) var celebration = 0.0
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
        pullPositions = state.round.pull?.stops.map(Double.init) ?? [0, 7, 14]
        lastPull = state.round.pull
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
            case .pulled(let p):
                // Show the frame's score before the next pull spins.
                beats.append(.pull(p))
            case .freeGamesWon(let n):
                beats.append(.banner("FREE GAMES", sub: "\(n) FREE FRAMES · EVERY ONE x2", seconds: 1.8))
            case .jackpot(let tier):
                beats.append(.banner("\(tier.title) JACKPOT", sub: "PAID TO YOUR WINNINGS", seconds: 2.4))
            case .counterOpened, .bought, .sold, .rerolled, .armed, .ballChosen:
                break
            }
        }
        if !spun && step.state.stops != shown.stops {
            beats.append(.spin(to: step.state.stops))
        }
        beats.append(.commit(step.state))
    }

    /// Beats that finished during the last `advance`, for the shell's
    /// haptics and sound. Cleared at the start of each advance.
    public private(set) var finished: [Beat] = []
    /// Moments that happened during the last `advance`, timed to the frame:
    /// the ball hitting the hump, rattling a lip, dropping; reels ticking;
    /// tally steps. Sound and effects hang off these.
    public private(set) var cues: [Cue] = []
    var lastTick = 0.0
    var shownSteps = 0

    /// 1 while a ball that could complete a pair into three of a kind is in
    /// the air: the slot's "will it land" moment.
    public var anticipation: Double {
        guard case .roll(let r, _) = beats.first else { return 0 }
        let have = shown.round.currentBalls.map(\.symbol)
        guard have.count == 2, case .pair = Payline.evaluate(have) else { return 0 }
        guard let b = ball, b.along > Table.standard.lane.length else { return 0 }
        let dropT = zip(r.events, r.eventTimes).first { e, _ in
            if case .dropped = e { true } else { e == .gutter }
        }?.1 ?? .infinity
        return beatTime / Self.rollSpeed + (r.path.first?.t ?? 0) < dropT - 0.02 ? 1 : 0
    }

    /// How fast presentation time runs right now (slow motion < 1).
    public var timeScale: Double { anticipation > 0 ? Self.anticipationScale : 1 }

    public mutating func advance(_ dt: Double) {
        finished = []
        cues = []
        clock += dt
        flash = max(0, flash - dt * 2.5)
        shake = max(0, shake - dt * 3)
        celebration = max(0, celebration - dt / 2.4)
        popups = popups.compactMap { p in
            var q = p; q.age += dt / p.life; return q.age < 1 ? q : nil
        }
        if let r = restingBall, clock > r.until { restingBall = nil }
        var remaining = dt
        while let beat = beats.first {
            if beatTime == 0 { begin(beat) }
            let scale = timeScale
            let left = beat.duration - beatTime
            if remaining * scale < left {
                let before = beatTime
                beatTime += remaining * scale
                during(beat, from: before)
                return
            }
            remaining -= max(left, 0) / scale
            let before = beatTime
            beatTime = beat.duration
            during(beat, from: before)
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
        case .roll(_, let b):
            trail = []
            cues.append(.launch)
            if b.ball == .comet { cues.append(.whoosh) }
        case .spin:
            spinFrom = reelPositions
            lastTick = 0
            cues.append(.reelTick)
        case .pull:
            pullFrom = pullPositions
            pullStopped = 0
            lastPull = nil
            lastTick = 0
            cues.append(.lever)
        case .tally:
            shownSteps = 0
        case .banner(let t, _, _):
            flash = max(flash, 0.4)
            cues.append(t == "FOUL" ? .foul : .banner(t))
            if t == "CLEARED" || t == "FREE GAMES" || t.hasSuffix("JACKPOT") || t == "YOU BEAT THE ARCADE" { celebration = 1 }
        case .commit, .restyle: break
        }
    }

    mutating func during(_ beat: Beat, from before: Double) {
        switch beat {
        case .roll(let r, _):
            // Shot events whose moment passed this frame.
            let t0 = r.path.first?.t ?? 0
            let a = before / Self.rollSpeed + t0, b = beatTime / Self.rollSpeed + t0
            for (e, et) in zip(r.events, r.eventTimes) where et > a && et <= b || (before == 0 && et == t0 && et <= b) {
                switch e {
                case .launched:
                    cues.append(.hump)
                    if case .roll(_, let b) = beat { shake = max(shake, b.ball == .comet ? 0.8 : 0.25) }
                case .lip: cues.append(.lip)
                case .backwall: cues.append(.backwall)
                case .landed: cues.append(.landed)
                case .dropped(let h): cues.append(.drop(h))
                case .gutter: cues.append(.gutter)
                case .rail: cues.append(.rail)
                case .hop: cues.append(.hop)
                case .dud, .settled: break
                }
            }
            let t = beatTime / Self.rollSpeed
            let sample = Self.sample(r.path, at: t)
            if let sample {
                trail.append(sample)
                if trail.count > 14 { trail.removeFirst(trail.count - 14) }
            }
        case .pull(let p):
            let spinning = beatTime < Self.pullStop(2, p)
            if spinning && beatTime - lastTick > 0.06 { lastTick = beatTime; cues.append(.reelTick) }
            for i in 0..<3 {
                let n = Double(Pull.strips[i].count)
                let end = Self.pullStop(i, p)
                let start = pullFrom.indices.contains(i) ? pullFrom[i] : 0
                var target = Double(p.stops[i])
                while target < start + n * Double(3 + i) { target += n }
                let u = min(1, beatTime / end)
                // Ease out with a small overshoot and settle: the reel
                // clunks into place instead of gliding.
                let eased = u < 1 ? 1 - pow(1 - u, 3) + 0.04 * sin(u * .pi) : 1
                pullPositions[i] = start + (target - start) * min(eased, 1.01)
                if u >= 1 { pullPositions[i] = target }
            }
            while pullStopped < 3 && beatTime >= Self.pullStop(pullStopped, p) { cues.append(.reelStop); pullStopped += 1 }
            if !spinning && lastPull == nil {
                lastPull = p
                if p.lineChips > 0 {
                    popups.append(Popup(text: "WIN \(p.lineChips)", anchor: .hud, kind: .chips, life: 1.4))
                    cues.append(.pullWin(p.lineChips))
                }
            }
        case .spin(let to):
            if beatTime - lastTick > 0.07 && beatTime < beat.duration * 0.8 { lastTick = beatTime; cues.append(.reelTick) }
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
        case .tally(let f):
            let k = min(f.steps.count, Int(beatTime / Self.tallyStep) + 1)
            while shownSteps < k {
                let st = f.steps[shownSteps]
                switch st.effect {
                case .mult, .timesMult: cues.append(.tallyMult(shownSteps))
                default: cues.append(.tallyChips(shownSteps))
                }
                shownSteps += 1
            }
        case .banner, .commit, .restyle:
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
            let text = b.hole == .gutter ? (r.rattles > 0 ? "SO CLOSE!" : "GUTTER") : "+\(b.chips)"
            popups.append(Popup(text: text, anchor: .hole(b.hole), kind: b.hole == .gutter ? .bad : .chips))
            if r.rattles > 0 { shake = max(shake, 0.35) }
            if b.hot {
                popups.append(Popup(text: "HOT SPOT! x2", anchor: .center, kind: .jackpot, life: 1.5))
                cues.append(.hotSpot)
                celebration = max(celebration, 0.7)
                flash = max(flash, 0.5)
            } else if b.hole.faceValue >= 50 {
                celebration = max(celebration, 0.45)
            }
            if b.scored && b.ball.pay >= 2 {
                popups.append(Popup(text: "\(b.ball.short) \(b.ball.payLabel)!", anchor: .hud, kind: .tickets, life: 1.2))
            }
            if b.slotHits > 0 {
                let text = b.combo > 1 ? "COMBO x\(b.combo)" : "TOP SLOT!"
                popups.append(Popup(text: text, anchor: .hud, kind: .mult, life: 1.4))
                cues.append(.combo(b.combo))
                flash = max(flash, 0.25 + 0.1 * Double(min(b.combo, 5)))
            }
        case .spin(let to):
            reelPositions = to.mapValues(Double.init)
            cues.append(.reelStop)
        case .pull(let p):
            pullPositions = p.stops.map(Double.init)
            lastPull = p
        case .tally(let f):
            let line: String
            switch f.payline {
            case .none: line = "\(f.total)"
            case .pair(let s): line = "PAIR OF \(s.rawValue.uppercased())S  \(f.total)"
            case .triple(let s): line = f.isJackpot ? "JACKPOT  \(f.total)" : "THREE \(s.rawValue.uppercased())S  \(f.total)"
            }
            popups.append(Popup(text: line, anchor: .center, kind: f.isJackpot ? .jackpot : .mult, life: 1.6))
            cues.append(f.isJackpot ? .jackpot : (f.payline == .none ? .frameDone : .lineWon))
            if f.payline != .none { celebration = max(celebration, f.isJackpot ? 1 : 0.6) }
            talliedBonus += f.total
        case .commit(let s):
            shown = s
            talliedBonus = 0
            reelPositions = s.stops.mapValues(Double.init)
            if let p = s.round.pull { pullPositions = p.stops.map(Double.init); lastPull = p }
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
        return (f, min(f.steps.count, Int(beatTime / Self.tallyStep) + 1))
    }

    /// When reel `i` of a pull stops. With two BONUS already showing on
    /// the first two reels the last one hangs on, the floor's oldest tease.
    public static func pullStop(_ i: Int, _ p: Pull) -> Double {
        let base = 0.7 + 0.3 * Double(i)
        return i == 2 && teases(p) ? base + 0.9 : base
    }

    static func teases(_ p: Pull) -> Bool {
        p.grid.joined().enumerated().filter { $0.element == .bonus && $0.offset % 3 < 2 }.count >= 2
    }

    /// Spin, then a beat to read the wins.
    public static func pullDuration(_ p: Pull) -> Double {
        pullStop(2, p) + (p.lineChips > 0 || p.triggersFreeGames ? 1.0 : 0.45)
    }

    /// The pull machine's reel `i` is teasing right now.
    public var teasing: Bool {
        guard case .pull(let p) = beats.first else { return false }
        return Self.teases(p) && beatTime > Self.pullStop(1, p) && beatTime < Self.pullStop(2, p)
    }

    /// Symbol at a fractional reel position and row offset, for drawing.
    public static func pullSymbol(reel: Int, at position: Double, row: Int, room: Room = .boardwalk) -> ReelSymbol {
        let strip = room.strips[reel]
        let i = (Int(position.rounded(.down)) + row) % strip.count
        return strip[(i + strip.count) % strip.count]
    }

    public var banner: (String, String, Double)? {
        guard case .banner(let a, let b, let s) = beats.first else { return nil }
        return (a, b, beatTime / s)
    }
}

/// A moment worth a sound or an effect.
public enum Cue: Hashable, Sendable {
    case launch, rail, hump, lip, backwall, landed, drop(Hole), gutter, hop, whoosh, hotSpot
    /// The lever going down; a pull's line wins, in chips.
    case lever, pullWin(Int)
    case reelTick, reelStop
    /// A ball matched the top slot; the combo level after it.
    case combo(Int)
    case tallyChips(Int), tallyMult(Int), frameDone, lineWon, jackpot
    case banner(String), foul
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
