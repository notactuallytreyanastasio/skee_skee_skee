/// One round: a target, a number of three-ball frames, and the balls so far.
public struct RoundState: Hashable, Sendable, Codable {
    public var kind: RoundKind
    public var target: Int
    public var framesTotal: Int
    public var frames: [FrameScore] = []
    /// Balls of the frame in progress (0...2 of them).
    public var currentBalls: [BallRecord] = []
    /// Consecutive scoring balls this round.
    public var streak = 0
    /// Power-up applied to the next throw.
    public var armed: PowerUp?

    public init(kind: RoundKind, target: Int, framesTotal: Int) {
        self.kind = kind; self.target = target; self.framesTotal = framesTotal
    }

    public var score: Int { frames.reduce(0) { $0 + $1.total } }
    public var ballsLeft: Int { (framesTotal - frames.count) * 3 - currentBalls.count }
}

public enum Phase: Hashable, Sendable, Codable {
    case throwing
    case prizeCounter(PrizeCounter)
    case lost
    case won
}

/// The whole run as a value. `(seed, [Action])` reproduces it exactly.
public struct RunState: Hashable, Sendable, Codable {
    public var config: RunConfig
    public var rng: SplitMix64
    public var seed: UInt64
    public var ante: Int
    public var boss: Boss
    public var round: RoundState
    public var phase: Phase
    public var setup: BoardSetup
    /// Where each hole's reel has stopped: index into `setup.reel(hole)`.
    public var stops: [Hole: Int]
    public var charms: [Charm]
    public var powerUps: [PowerUp]
    public var tickets: Int
    /// Jackpot meter. Rattles and gutters add heat.
    public var heat: Int
    /// The next frame plays at double mult.
    public var fever: Bool
    public var stats: RunStats
}

public struct RunStats: Hashable, Sendable, Codable {
    public var balls = 0
    public var holes: [Hole: Int] = [:]
    public var jackpots = 0
    public var rattles = 0
    public var bestFrame = 0
    public var roundsCleared = 0
}

public enum Action: Hashable, Sendable, Codable {
    case throwBall(Launch)
    /// The thumb touched past the crease. The ball is spent, scores nothing.
    case foul
    /// Arm the power-up at this inventory index for the next throw.
    case arm(Int)
    /// Buy offer at index; stamps and gilds need a target hole.
    case buy(Int, target: Hole?)
    case reroll
    case sell(Int)
    case leaveCounter
}

public enum ActionError: Error, Hashable, Sendable {
    case wrongPhase
    case noSuchOffer
    case noSuchItem
    case cantAfford
    case slotsFull
    case needsTarget
    case alreadyArmed
    case reelTooShort
}

extension RunState {
    /// The symbol a hole is showing right now; the next ball into it gets it.
    public func showing(_ hole: Hole) -> Symbol {
        let reel = setup.reel(hole)
        return reel[(stops[hole] ?? 0) % reel.count]
    }
}

/// Things the shell should show or play. Order is the order they happened.
public enum GameEvent: Hashable, Sendable {
    case shot(ShotResult, BallRecord)
    case fouled
    case frameScored(FrameScore)
    case feverLit
    case roundCleared(score: Int, target: Int, payout: Payout)
    case roundFailed(score: Int, target: Int)
    case counterOpened
    case bought(Offer)
    case sold(Charm)
    case rerolled
    case armed(PowerUp)
    case roundStarted(RoundKind, target: Int)
    case anteStarted(Int, boss: Boss)
    case runWon
}

public struct Payout: Hashable, Sendable, Codable {
    public var base: Int
    public var overkill: Int
    public var interest: Int
    public var total: Int { base + overkill + interest }
}

public struct Step: Sendable {
    public var state: RunState
    public var events: [GameEvent]
}
