/// A simple, honest player: aims for the hole that best completes the
/// current payline, buys charms it can afford in a fixed preference order,
/// stamps sevens onto the 40, and fires power-ups on the third ball.
/// Not clever. It is a yardstick for balance, not an opponent.
public struct BotRun: Sendable {
    public var final: RunState
    public var actions: [Action]
    public var events: [GameEvent]
}

public func playBotRun(seed: UInt64, skill: Skill, config: RunConfig = .standard, room: Room = .boardwalk,
                       books: inout [Table: AimBook]) -> BotRun {
    var s = newRun(seed: seed, config: config, room: room)
    var hand = SplitMix64(seed: seed ^ 0xB07)
    var actions: [Action] = []
    var events: [GameEvent] = []
    var rates: [RateKey: [Hole: [Hole: Double]]] = [:]
    func act(_ a: Action) -> Bool {
        guard case .success(let step) = apply(a, to: s) else { return false }
        s = step.state; actions.append(a); events += step.events
        return true
    }

    while actions.count < 5000 {
        switch s.phase {
        case .won, .lost:
            return BotRun(final: s, actions: actions, events: events)
        case .throwing where s.round.pull == nil:
            // Max bet when it can keep a cushion for the counter.
            _ = act(.pull(s.tickets >= 8 ? .five : s.tickets >= 4 ? .three : .one))
        case .throwing:
            if s.round.currentBalls.count == 2, !s.powerUps.isEmpty { _ = act(.arm(0)) }
            let t = table(for: s)
            if books[t] == nil { books[t] = AimBook(table: t) }
            let book = books[t]!
            let key = RateKey(table: t, skill: skill)
            if rates[key] == nil { rates[key] = landings(book, t, skill) }
            let want = chooseHole(s, book, rates[key]!)
            let ideal = book.best[want]?.launch ?? Launch(power: 0.6, aim: 0)
            _ = act(.throwBall(skill.perturb(ideal, rng: &hand)))
        case .prizeCounter(let c):
            var bought = false
            for (i, offer) in c.offers.enumerated() {
                guard let offer, offer.cost <= s.tickets else { continue }
                switch offer {
                case .charm(let ch) where Self_charmPreference.firstIndex(of: ch).map({ $0 < 10 }) ?? false:
                    bought = act(.buy(i, target: nil))
                case .stamp(.seven), .stamp(.clover):
                    bought = act(.buy(i, target: .ring40))
                case .gild:
                    bought = act(.buy(i, target: .ring50))
                case .powerUp:
                    bought = s.tickets - offer.cost >= 5 && act(.buy(i, target: nil))
                default:
                    break
                }
                if bought { break }
            }
            if !bought { _ = act(.leaveCounter) }
        }
    }
    return BotRun(final: s, actions: actions, events: events)
}

public func playBotRun(seed: UInt64, skill: Skill, config: RunConfig = .standard, room: Room = .boardwalk) -> BotRun {
    var books: [Table: AimBook] = [:]
    return playBotRun(seed: seed, skill: skill, config: config, room: room, books: &books)
}

private let Self_charmPreference: [Charm] = [
    .multBall, .hotStreak, .heavyHand, .ladder, .sevenSeas, .extraBall,
    .nearMiss, .luckyPenny, .bellRinger, .ticketMuncher, .gutterRat,
    .evenSteven, .cornerOffice, .glassCannon, .hingeWhisperer,
]

struct RateKey: Hashable { var table: Table; var skill: Skill }

/// Monte Carlo: where this hand's balls really land when it aims at the
/// centre of each hole's best window, as a share per landing hole. Seeded,
/// so bots stay deterministic.
func landings(_ book: AimBook, _ table: Table, _ skill: Skill, samples: Int = 64) -> [Hole: [Hole: Double]] {
    var rng = SplitMix64(seed: 0x5EED)
    var out: [Hole: [Hole: Double]] = [:]
    // Iterate in a fixed order: dictionary order is not stable, and the
    // shared rng would hand different noise to different holes.
    for hole in BoardSetup.reelHoles {
        guard let w = book.best[hole] else { continue }
        var spread: [Hole: Double] = [:]
        for _ in 0..<samples { spread[simulateShot(skill.perturb(w.launch, rng: &rng), on: table).hole, default: 0] += 1 / Double(samples) }
        out[hole] = spread
    }
    return out
}

/// Expected-value aiming over everything a shot can do, not just the hole
/// aimed at. Hit rate times value is the obvious version and it is wrong: a
/// missed pocket is a gutter, a missed ring is usually another ring, and
/// ignoring that made a steady hand chase pockets into 39% gutters and lose
/// to a shakier one that could not be tempted.
private func chooseHole(_ s: RunState, _ book: AimBook, _ rates: [Hole: [Hole: Double]]) -> Hole {
    let have = s.round.currentBalls.map(\.symbol)
    let lineNow = Payline.evaluate(have).addedMult
    func value(_ hole: Hole) -> Double {
        // A throw that matches no target breaks the combo, and a gutter
        // always does: the streak is worth what its next link would pay.
        let streak = 40 * TopSlot.comboMult(hits: 1, level: s.round.combo + 1)
        guard hole != .gutter else { return s.round.combo > 0 ? -streak : 0 }
        let symbol = s.showing(hole)
        let lineGain = Payline.evaluate(have + [symbol]).addedMult - lineNow
        var chips = s.setup.chips(for: hole)
        if s.round.kind == .boss { chips = s.boss.chips(for: hole, base: chips) }
        let hits = s.topSlot.hits(symbol)
        let combo = hits > 0 ? 40 * TopSlot.comboMult(hits: hits, level: s.round.combo + 1) : (s.round.combo > 0 ? -streak : 0)
        return Double(chips) + 40 * lineGain + combo
    }
    var best: (Hole, Double) = (.ring10, -1)
    for hole in BoardSetup.reelHoles {
        let ev = (rates[hole] ?? [:]).reduce(0) { $0 + $1.value * value($1.key) }
        if ev > best.1 { best = (hole, ev) }
    }
    return best.0
}
