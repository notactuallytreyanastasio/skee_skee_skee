/// Start a run. The first ante's boss is drawn immediately so it can be
/// shown from the start.
public func newRun(seed: UInt64, config: RunConfig = .standard) -> RunState {
    var rng = SplitMix64(seed: seed)
    let boss = rng.pick(Boss.allCases)
    var s = RunState(
        config: config, rng: rng, seed: seed, ante: 1, boss: boss,
        round: RoundState(kind: .warmup, target: 0, framesTotal: 0),
        phase: .throwing, setup: .standard, stops: [:], topSlot: .empty, charms: [], powerUps: [],
        tickets: config.startTickets, heat: 0, fever: false, stats: RunStats())
    s.round = freshRound(.warmup, in: s)
    spinReels(&s)
    return s
}

/// Every reel lands on a fresh seeded stop.
private func spinReels(_ s: inout RunState) {
    for hole in BoardSetup.reelHoles {
        s.stops[hole] = s.rng.nextInt(below: s.setup.reel(hole).count)
    }
}

/// The table the next ball is thrown on: ante difficulty, then the boss (on
/// boss rounds), then the armed power-up.
public func table(for s: RunState) -> Table {
    var t = difficultyTable(ante: s.ante, antes: s.config.antes)
    if s.round.kind == .boss { t = s.boss.modify(t) }
    if let p = s.round.armed { t = p.modify(t) }
    return t
}

/// The single entry point for changing a run. Pure: invalid actions are
/// rejected with a typed error and the input state is untouched.
public func apply(_ action: Action, to s: RunState) -> Result<Step, ActionError> {
    switch (action, s.phase) {
    case (.pull(let bet), .throwing): pull(bet, s)
    case (.throwBall, .throwing) where s.round.pull == nil, (.foul, .throwing) where s.round.pull == nil: .failure(.needsPull)
    case (.throwBall(let l), .throwing): .success(throwBall(l, s))
    case (.foul, .throwing): .success(foul(s))
    case (.arm(let i), .throwing): arm(i, s)
    case (.buy(let i, let target), .prizeCounter(let c)): buy(i, target, c, s)
    case (.reroll, .prizeCounter(let c)): reroll(c, s)
    case (.sell(let i), .prizeCounter): sell(i, s)
    case (.leaveCounter, .prizeCounter): .success(leaveCounter(s))
    default: .failure(.wrongPhase)
    }
}

// MARK: - The pull

/// Pull the lever: pay the bet, spin, read the window. Its centre row
/// becomes the frame's targets; line wins wait in the pull until the frame
/// is scored.
private func pull(_ bet: Bet, _ s0: RunState) -> Result<Step, ActionError> {
    guard s0.round.pull == nil else { return .failure(.alreadyPulled) }
    guard s0.tickets >= bet.cost else { return .failure(.cantAfford) }
    var s = s0
    s.tickets -= bet.cost
    s.round.lastBet = bet
    return .success(spin(Pull.spin(bet: bet, &s.rng), s))
}

private func spin(_ p: Pull, _ s0: RunState) -> Step {
    var s = s0
    var events: [GameEvent] = [.pulled(p)]
    s.round.pull = p
    s.topSlot = TopSlot(symbols: p.targets)
    s.stats.pulls += 1
    if p.triggersFreeGames {
        s.round.freeLeft += Pull.freeGamesAwarded
        s.round.framesTotal += Pull.freeGamesAwarded
        s.stats.freeGames += Pull.freeGamesAwarded
        events.append(.freeGamesWon(Pull.freeGamesAwarded))
    }
    if let tier = p.jackpot {
        s.stats.jackpotTiers[tier, default: 0] += 1
        events.append(.jackpot(tier))
    }
    return Step(state: s, events: events)
}

// MARK: - Throwing

private func freshRound(_ kind: RoundKind, in s: RunState) -> RoundState {
    var frames = s.config.framesPerRound
    if s.charms.contains(.extraBall) { frames += 1 }
    if kind == .boss { frames += s.boss.frameDelta }
    return RoundState(kind: kind, target: s.config.target(ante: s.ante, kind: kind), framesTotal: frames)
}

private func foul(_ s0: RunState) -> Step {
    var s = s0
    s.round.armed = nil
    s.round.currentBalls.append(BallRecord(hole: .gutter, symbol: .blank, chips: 0, foul: true))
    s.round.combo = 0
    s.stats.balls += 1
    spinReels(&s)
    return finishBall(s, [.fouled])
}

private func throwBall(_ launch: Launch, _ s0: RunState) -> Step {
    var s = s0
    var events: [GameEvent] = []
    let shot = simulateShot(launch, on: table(for: s))
    let armed = s.round.armed
    var chips = s.setup.chips(for: shot.hole)
    if s.round.kind == .boss { chips = s.boss.chips(for: shot.hole, base: chips) }
    if armed == .goldenBall { chips *= 3 }
    let symbol = armed == .wildBall && shot.hole != .gutter ? Symbol.clover : s.showing(shot.hole)
    let hits = s.topSlot.hits(symbol)
    s.round.combo = hits > 0 ? s.round.combo + 1 : 0
    let record = BallRecord(
        hole: shot.hole, symbol: symbol,
        chips: chips, rattles: shot.rattles, fold: launch.fold,
        slotHits: hits, combo: s.round.combo)
    s.round.armed = nil
    s.round.currentBalls.append(record)
    s.heat += shot.rattles + (shot.hole == .gutter ? 1 : 0)
    s.stats.balls += 1
    s.stats.rattles += shot.rattles
    s.stats.holes[shot.hole, default: 0] += 1
    events.append(.shot(shot, record))
    if armed != .hold { spinReels(&s) }
    return finishBall(s, events)
}

/// After any ball: score the frame if it is full, end the round if it was
/// the last frame.
private func finishBall(_ s0: RunState, _ events0: [GameEvent]) -> Step {
    var s = s0, events = events0
    guard s.round.currentBalls.count == s.config.ballsPerFrame else { return Step(state: s, events: events) }

    let context = ScoringContext(
        charms: s.charms, streakBefore: s.round.streak, fever: s.fever,
        pairsPay: s.round.kind != .boss || s.boss.pairsPay, pull: s.round.pull)
    let frame = scoreFrame(s.round.currentBalls, context: context)
    s.round.frames.append(frame)
    s.round.currentBalls = []
    s.round.pull = nil
    s.round.streak = frame.streakAfter
    s.tickets += frame.tickets
    s.fever = false
    if frame.isJackpot { s.stats.jackpots += 1 }
    s.stats.bestFrame = max(s.stats.bestFrame, frame.total)
    s.stats.points += frame.total
    events.append(.frameScored(frame))
    if s.heat >= s.config.feverHeat {
        s.heat -= s.config.feverHeat
        s.fever = true
        events.append(.feverLit)
    }

    guard s.round.frames.count == s.round.framesTotal else {
        // A free game: the machine pulls for you, at the bet that won it.
        guard s.round.freeLeft > 0 else { return Step(state: s, events: events) }
        s.round.freeLeft -= 1
        let step = spin(Pull.spin(bet: s.round.lastBet, free: true, &s.rng), s)
        return Step(state: step.state, events: events + step.events)
    }
    return endRound(s, events)
}

private func endRound(_ s0: RunState, _ events0: [GameEvent]) -> Step {
    var s = s0, events = events0
    let score = s.round.score, target = s.round.target
    guard score >= target else {
        s.phase = .lost
        events.append(.roundFailed(score: score, target: target))
        return Step(state: s, events: events)
    }
    let c = s.config
    let over = Double(score) / Double(max(target, 1)) - 1
    let payout = Payout(
        base: c.roundTickets[s.round.kind] ?? 3,
        overkill: min(c.overkillCap, Int((over / c.overkillStep).rounded(.down))),
        interest: min(c.interestCap, s.tickets / c.interestPer))
    s.tickets += payout.total
    s.stats.roundsCleared += 1
    events.append(.roundCleared(score: score, target: target, payout: payout))
    if s.round.kind == .boss && s.ante >= c.antes {
        s.phase = .won
        events.append(.runWon)
        return Step(state: s, events: events)
    }
    s.phase = .prizeCounter(PrizeCounter(offers: rollOffers(&s), rerollCost: 1))
    events.append(.counterOpened)
    return Step(state: s, events: events)
}

private func arm(_ i: Int, _ s0: RunState) -> Result<Step, ActionError> {
    guard s0.powerUps.indices.contains(i) else { return .failure(.noSuchItem) }
    guard s0.round.armed == nil else { return .failure(.alreadyArmed) }
    var s = s0
    let p = s.powerUps.remove(at: i)
    s.round.armed = p
    return .success(Step(state: s, events: [.armed(p)]))
}

// MARK: - Prize counter

private func rollOffers(_ s: inout RunState) -> [Offer?] {
    let unowned = Charm.allCases.filter { !s.charms.contains($0) }
    let charms = Array(s.rng.shuffled(unowned).prefix(2)).map(Offer.charm)
    let stampSymbols: [Symbol] = [.cherry, .bell, .bar, .seven, .diamond, .clover]
    let edit: Offer = switch s.rng.nextInt(below: 4) {
    case 0: .gild
    case 1: .purge
    default: .stamp(s.rng.pick(stampSymbols))
    }
    let power = Offer.powerUp(s.rng.pick(PowerUp.allCases))
    return Array((charms + [edit, power]).prefix(s.config.offerCount))
}

private func buy(_ i: Int, _ target: Hole?, _ c0: PrizeCounter, _ s0: RunState) -> Result<Step, ActionError> {
    guard c0.offers.indices.contains(i), let offer = c0.offers[i] else { return .failure(.noSuchOffer) }
    guard s0.tickets >= offer.cost else { return .failure(.cantAfford) }
    var s = s0, c = c0
    switch offer {
    case .charm(let charm):
        guard s.charms.count < s.config.charmSlots else { return .failure(.slotsFull) }
        s.charms.append(charm)
    case .powerUp(let p):
        guard s.powerUps.count < s.config.powerUpSlots else { return .failure(.slotsFull) }
        s.powerUps.append(p)
    case .stamp(let symbol):
        guard let hole = target, hole != .gutter else { return .failure(.needsTarget) }
        s.setup.reels[hole, default: []].append(symbol)
    case .purge:
        guard let hole = target, hole != .gutter else { return .failure(.needsTarget) }
        var reel = s.setup.reel(hole)
        guard reel.count > 1 else { return .failure(.reelTooShort) }
        reel.remove(at: (s.stops[hole] ?? 0) % reel.count)
        s.setup.reels[hole] = reel
        s.stops[hole] = 0
    case .gild:
        guard let hole = target, hole != .gutter else { return .failure(.needsTarget) }
        s.setup.gild[hole, default: 0] += Offer.gildAmount
    }
    s.tickets -= offer.cost
    c.offers[i] = nil
    s.phase = .prizeCounter(c)
    return .success(Step(state: s, events: [.bought(offer)]))
}

private func reroll(_ c0: PrizeCounter, _ s0: RunState) -> Result<Step, ActionError> {
    guard s0.tickets >= c0.rerollCost else { return .failure(.cantAfford) }
    var s = s0
    s.tickets -= c0.rerollCost
    s.phase = .prizeCounter(PrizeCounter(offers: rollOffers(&s), rerollCost: c0.rerollCost + 1))
    return .success(Step(state: s, events: [.rerolled]))
}

private func sell(_ i: Int, _ s0: RunState) -> Result<Step, ActionError> {
    guard s0.charms.indices.contains(i) else { return .failure(.noSuchItem) }
    var s = s0
    let charm = s.charms.remove(at: i)
    s.tickets += charm.cost / 2
    return .success(Step(state: s, events: [.sold(charm)]))
}

private func leaveCounter(_ s0: RunState) -> Step {
    var s = s0
    var events: [GameEvent] = []
    if let next = s.round.kind.next {
        s.round = freshRound(next, in: s)
    } else {
        s.ante += 1
        s.boss = s.rng.pick(Boss.allCases)
        s.round = freshRound(.warmup, in: s)
        events.append(.anteStarted(s.ante, boss: s.boss))
    }
    s.phase = .throwing
    events.append(.roundStarted(s.round.kind, target: s.round.target))
    return Step(state: s, events: events)
}
