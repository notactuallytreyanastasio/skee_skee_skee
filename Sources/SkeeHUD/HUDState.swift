import CoreGraphics
import SkeeCore
import SkeeRender

/// Everything the HUD draws, derived purely from the presentation plus the
/// few facts only the shell knows (where holes are on screen, what the
/// player has selected). Views never reach into game state directly.
public struct HUDState: Sendable {
    public enum Screen: Hashable, Sendable { case title, game }

    public var screen: Screen = .game
    public var ante = 1
    public var antes = 8
    public var roundTitle = ""
    public var isBoss = false
    public var bossName = ""
    public var bossBlurb = ""
    public var score = 0
    public var target = 1
    public var tickets = 0
    public var heat = 0
    public var heatMax = 10
    public var fever = false
    /// The top slot's reels, as positions on `TopSlot.strip` (fractional
    /// while spinning), and the combo running into the next throw.
    public var topSlot: [Double] = [0, 1, 2]
    public var combo = 0
    /// This frame's three reel stops so far (nil = not thrown yet).
    public var frame: [Symbol?] = [nil, nil, nil]
    public var frameNumber = 1
    public var framesTotal = 3
    public var ballsLeft = 9
    public var charms: [Charm] = []
    public var powerUps: [PowerUp] = []
    public var armed: PowerUp?
    public var counter: PrizeCounter?
    public var over: (won: Bool, stats: RunStats)?
    public var tally: Tally?
    public var banner: Banner?
    public var popups: [ScreenPopup] = []
    public var selectedOffer: Int?
    public var selectedCharm: Int?
    public var busy = false
    public var firstThrow = false
    /// Plain-words explanation of the slot right now.
    public var hint: Hint?
    /// Recent throws: power 0...1 and where they went, newest last.
    public var throwsMeter: [ThrowMark] = []
    /// Winnings and the prize shelf, kept between runs; the shop overlay.
    public var wallet = Wallet()
    /// The walkthrough's card for this moment, if one is running.
    public var coach: CoachCard?
    public var shopOpen = false
    /// The thumb's recent path, for a fading trail. Age 0...1.
    public var trail: [(CGPoint, Double)] = []
    /// The waiting ball's line: a straight flick rolls along it and lands
    /// somewhere on it. Screen points from the ball up the lane and the
    /// board; empty when not throwing. `aiming` while the thumb is down.
    public var guide: [CGPoint] = []
    public var aiming = false

    public struct Hint: Sendable {
        public var text: String
        public var symbol: Symbol?
        public var after: String = ""
        public var hot = false
    }

    public struct Tally: Sendable { public var chips: Int; public var mult: Double; public var label: String }
    public struct Banner: Sendable { public var title: String; public var sub: String; public var progress: Double }
    public struct ScreenPopup: Sendable { public var text: String; public var kind: Popup.Kind; public var at: CGPoint; public var age: Double }

    public init() {}

    /// Build from a presentation. `holeOnScreen` places popups over holes.
    public static func make(_ p: Presentation, holeOnScreen: (Hole) -> CGPoint, center: CGPoint,
                            selectedOffer: Int? = nil, selectedCharm: Int? = nil, screen: Screen = .game) -> HUDState {
        let s = p.shown
        var h = HUDState()
        h.screen = screen
        h.ante = s.ante; h.antes = s.config.antes
        h.roundTitle = s.round.kind.title.uppercased()
        h.isBoss = s.round.kind == .boss
        h.bossName = s.boss.name.uppercased(); h.bossBlurb = s.boss.blurb
        h.tickets = s.tickets
        h.heat = s.heat; h.heatMax = s.config.feverHeat; h.fever = s.fever
        h.frameNumber = min(s.round.frames.count + 1, s.round.framesTotal)
        h.framesTotal = s.round.framesTotal
        h.ballsLeft = s.round.ballsLeft
        h.charms = s.charms; h.powerUps = s.powerUps; h.armed = s.round.armed
        h.busy = p.isBusy
        h.topSlot = p.slotPositions
        h.combo = s.round.combo
        h.selectedOffer = selectedOffer; h.selectedCharm = selectedCharm
        h.firstThrow = s.ante == 1 && s.round.kind == .warmup && s.round.frames.isEmpty && s.round.currentBalls.isEmpty
        if case .prizeCounter(let c) = s.phase, !p.isBusy { h.counter = c }
        if !p.isBusy {
            if case .lost = s.phase { h.over = (false, s.stats) }
            if case .won = s.phase { h.over = (true, s.stats) }
        }

        // Frame symbols: the frame being tallied, else the balls so far.
        let balls = p.tallyProgress?.0.balls ?? s.round.currentBalls
        for i in 0..<3 { h.frame[i] = i < balls.count ? balls[i].symbol : nil }

        var score = s.round.score + p.talliedBonus
        if let (f, k) = p.tallyProgress {
            let (chips, mult) = fold(f.steps.prefix(k))
            score += k >= f.steps.count ? f.total : Int(Double(chips) * mult)
            h.tally = Tally(chips: chips, mult: mult, label: k > 0 ? stepLabel(f, f.steps[k - 1]) : "")
        }
        h.score = score; h.target = s.round.target

        if let (t, sub, u) = p.banner { h.banner = Banner(title: t, sub: sub, progress: u) }
        h.throwsMeter = p.recentThrows
        if !p.isBusy, case .throwing = s.phase { h.hint = hint(for: s.round.currentBalls.map(\.symbol)) }
        h.popups = p.popups.map { pop in
            let at: CGPoint = switch pop.anchor {
            case .hole(let hole): holeOnScreen(hole)
            case .center, .hud: center
            }
            return ScreenPopup(text: pop.text, kind: pop.kind, at: at, age: pop.age)
        }
        return h
    }

    /// What the slot needs next, in words.
    public static func hint(for have: [Symbol]) -> Hint {
        let line = Payline.evaluate(have)
        switch (have.count, line) {
        case (0, _):
            return Hint(text: "3 balls = 1 line · match symbols for MULT")
        case (1, _):
            if have[0] == .blank { return Hint(text: "gutter · the next two can still pair") }
            return Hint(text: "match the", symbol: have[0].isWild ? nil : have[0], after: "· glowing rings pair it")
        case (2, .pair(let s)):
            return Hint(text: "PAIR! one more", symbol: s, after: "= ×\(num(1 + s.tripleMult))", hot: true)
        case (2, _):
            return Hint(text: "no match yet · glowing rings pair")
        default:
            return Hint(text: "")
        }
    }

    public static func fold<S: Sequence>(_ steps: S) -> (Int, Double) where S.Element == ScoreStep {
        var chips = 0, mult = 1.0
        for st in steps {
            switch st.effect {
            case .base(let c, let m): chips = c; mult = m
            case .chips(let c): chips += c
            case .mult(let m): mult += m
            case .timesMult(let x): mult *= x
            case .tickets, .note: break
            }
        }
        return (chips, mult)
    }

    static func num(_ x: Double) -> String { x == x.rounded() ? "\(Int(x))" : String(format: "%.1f", x) }

    public static func stepLabel(_ f: FrameScore, _ st: ScoreStep) -> String {
        let what: String = switch st.effect {
        case .base: ""
        case .chips(let c): "+\(c) chips"
        case .mult(let m): "+\(num(m)) mult"
        case .timesMult(let x): "x\(num(x)) mult"
        case .tickets(let t): "+\(t) tickets"
        case .note(let n): n
        }
        switch st.source {
        case .base: return "frame"
        case .ball(let i): return "ball \(i + 1)  \(what)"
        case .slot(let i):
            let b = f.balls[i]
            return b.combo > 1 ? "top slot combo x\(b.combo)  \(what)" : "top slot  \(what)"
        case .payline:
            switch f.payline {
            case .none: return what
            case .pair(let s): return "pair of \(s.rawValue)s  \(what)"
            case .triple(let s): return "three \(s.rawValue)s  \(what)"
            }
        case .charm(let c): return "\(c.name)  \(what)"
        case .fever: return "fever  \(what)"
        }
    }
}
