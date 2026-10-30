/// One thrown ball as the scorer sees it: no physics, just what it hit and
/// the few facts about the throw that charms care about.
public struct BallRecord: Hashable, Sendable, Codable {
    public var hole: Hole
    public var symbol: Symbol
    public var chips: Int
    public var rattles: Int
    public var fold: Double

    public init(hole: Hole, symbol: Symbol, chips: Int, rattles: Int = 0, fold: Double = 0) {
        self.hole = hole; self.symbol = symbol; self.chips = chips
        self.rattles = rattles; self.fold = fold
    }

    public var scored: Bool { hole != .gutter }
}

public struct ScoringContext: Hashable, Sendable {
    public var charms: [Charm]
    /// Consecutive scoring balls this round before this frame.
    public var streakBefore: Int
    /// Jackpot meter was full going into this frame: everything doubles.
    public var fever: Bool
    /// False under The House boss: pairs are still read, but pay nothing.
    public var pairsPay: Bool

    public init(charms: [Charm] = [], streakBefore: Int = 0, fever: Bool = false, pairsPay: Bool = true) {
        self.charms = charms; self.streakBefore = streakBefore; self.fever = fever
        self.pairsPay = pairsPay
    }
}

/// Every change to chips or mult, in the order applied. The shell plays
/// these back one by one, Balatro-style; the total is just their fold.
public struct ScoreStep: Hashable, Sendable, Codable {
    public enum Source: Hashable, Sendable, Codable {
        case base, ball(Int), payline, charm(Charm), fever
    }
    public enum Effect: Hashable, Sendable, Codable {
        case base(chips: Int, mult: Double)
        case chips(Int)
        case mult(Double)
        case timesMult(Double)
        case tickets(Int)
        case note(String)
    }
    public var source: Source
    public var effect: Effect
}

public struct FrameScore: Hashable, Sendable, Codable {
    public var balls: [BallRecord]
    public var payline: Payline
    public var steps: [ScoreStep]
    public var chips: Int
    public var mult: Double
    public var tickets: Int
    public var streakAfter: Int

    public var total: Int { Int((Double(chips) * mult).rounded(.down)) }
    public var isJackpot: Bool { payline == .triple(.seven) || payline == .triple(.diamond) }
}

/// Score one three-ball frame. Order: base, each ball's chips, flat symbol
/// chips, the payline, charms left to right, fever. Order matters because
/// `timesMult` multiplies whatever mult exists at that point.
public func scoreFrame(_ balls: [BallRecord], context: ScoringContext) -> FrameScore {
    var steps: [ScoreStep] = [ScoreStep(source: .base, effect: .base(chips: 0, mult: 1))]
    for (i, b) in balls.enumerated() {
        steps.append(ScoreStep(source: .ball(i), effect: .chips(b.chips)))
        if b.symbol.flatChips > 0 {
            steps.append(ScoreStep(source: .ball(i), effect: .chips(b.symbol.flatChips)))
        }
    }
    let payline = Payline.evaluate(balls.map(\.symbol))
    if case .pair = payline, !context.pairsPay {
        steps.append(ScoreStep(source: .payline, effect: .note("the house keeps pairs")))
    } else if payline != .none {
        steps.append(ScoreStep(source: .payline, effect: .mult(payline.addedMult)))
    }

    var streak = context.streakBefore
    for b in balls { streak = b.scored ? streak + 1 : 0 }
    let view = FrameView(balls: balls, payline: payline, streakAfter: streak)
    for charm in context.charms {
        for e in charm.effects(on: view) { steps.append(ScoreStep(source: .charm(charm), effect: e)) }
    }
    if context.fever {
        steps.append(ScoreStep(source: .fever, effect: .timesMult(2)))
    }

    var chips = 0, mult = 1.0, tickets = 0
    for s in steps {
        switch s.effect {
        case .base(let c, let m): chips = c; mult = m
        case .chips(let c): chips += c
        case .mult(let m): mult += m
        case .timesMult(let x): mult *= x
        case .tickets(let t): tickets += t
        case .note: break
        }
    }
    return FrameScore(balls: balls, payline: payline, steps: steps, chips: chips,
                      mult: mult, tickets: tickets, streakAfter: streak)
}

/// What a charm is allowed to look at.
public struct FrameView: Hashable, Sendable {
    public var balls: [BallRecord]
    public var payline: Payline
    public var streakAfter: Int

    func count(_ where: (BallRecord) -> Bool) -> Int { balls.filter(`where`).count }
}
