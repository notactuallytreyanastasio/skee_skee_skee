import Testing
@testable import SkeeCore

/// Find a straight-ish launch that lands in `hole` on `table`.
func launch(for hole: Hole, on table: Table = .standard) -> Launch {
    for aim in [0.0, 0.3, -0.3, 0.6, -0.6, 1, -1] {
        for start in [0.0, 1, -1] {
            for i in 0...200 {
                let l = Launch(power: Double(i) / 200, aim: aim, start: start)
                if simulateShot(l, on: table).hole == hole { return l }
            }
        }
    }
    fatalError("no launch reaches \(hole)")
}

func throwing(_ s: RunState, _ hole: Hole, times: Int = 1) throws -> (RunState, [GameEvent]) {
    var state = s, events: [GameEvent] = []
    for _ in 0..<times {
        let step = try apply(.throwBall(launch(for: hole, on: table(for: state))), to: state).get()
        state = step.state
        events += step.events
    }
    return (state, events)
}

@Suite("Run")
struct RunTests {
    @Test func newRunStartsAtTheFirstWarmup() {
        let s = newRun(seed: 1)
        #expect(s.ante == 1)
        #expect(s.round.kind == .warmup)
        #expect(s.phase == .throwing)
        #expect(s.round.target == RunConfig.standard.target(ante: 1, kind: .warmup))
        #expect(s.tickets == RunConfig.standard.startTickets)
    }

    @Test func sameSeedSameBoss() {
        #expect(newRun(seed: 5).boss == newRun(seed: 5).boss)
        let bosses = Set((0..<40).map { newRun(seed: UInt64($0)).boss })
        #expect(bosses.count > 3)
    }

    @Test func threeBallsMakeAFrame() throws {
        let (s, events) = try throwing(newRun(seed: 1), .ring30, times: 3)
        #expect(s.round.frames.count == 1)
        #expect(s.round.currentBalls.isEmpty)
        #expect(events.contains { if case .frameScored = $0 { true } else { false } })
        #expect(s.round.score == s.round.frames[0].total)
    }

    @Test func clearingARoundOpensThePrizeCounterAndPays() throws {
        var s = newRun(seed: 1)
        s.round.target = 10
        let (after, events) = try throwing(s, .ring10, times: 9)
        guard case .prizeCounter(let counter) = after.phase else {
            Issue.record("expected prize counter, got \(after.phase)"); return
        }
        #expect(counter.offers.count == 4)
        #expect(after.tickets > s.tickets)
        #expect(events.contains { if case .roundCleared = $0 { true } else { false } })
    }

    @Test func missingTheTargetEndsTheRun() throws {
        var s = newRun(seed: 1)
        s.round.target = 1_000_000
        let (after, _) = try throwing(s, .gutter, times: 9)
        #expect(after.phase == .lost)
    }

    @Test func throwingOutsideTheLaneIsRejected() {
        var s = newRun(seed: 1)
        s.phase = .lost
        #expect(throws: ActionError.wrongPhase) { try apply(.throwBall(Launch(power: 0.5, aim: 0)), to: s).get() }
    }

    @Test func replayIsExact() throws {
        let actions: [Action] = (0..<9).map { i in .throwBall(Launch(power: 0.4 + Double(i) * 0.03, aim: 0)) }
        let a = try actions.reduce(newRun(seed: 9)) { try apply($1, to: $0).get().state }
        let b = try actions.reduce(newRun(seed: 9)) { try apply($1, to: $0).get().state }
        #expect(a == b)
    }

    @Test func leavingTheCounterAdvancesRoundAndAnte() throws {
        var s = newRun(seed: 1)
        s.phase = .prizeCounter(PrizeCounter(offers: [], rerollCost: 1))
        s = try apply(.leaveCounter, to: s).get().state
        #expect(s.round.kind == .feature)
        s.phase = .prizeCounter(PrizeCounter(offers: [], rerollCost: 1))
        s = try apply(.leaveCounter, to: s).get().state
        #expect(s.round.kind == .boss)
        let bossTarget = s.round.target
        #expect(bossTarget == RunConfig.standard.target(ante: 1, kind: .boss))
        s.phase = .prizeCounter(PrizeCounter(offers: [], rerollCost: 1))
        s = try apply(.leaveCounter, to: s).get().state
        #expect(s.ante == 2)
        #expect(s.round.kind == .warmup)
    }

    @Test func beatingTheLastBossWinsTheRun() throws {
        var s = newRun(seed: 1)
        s.ante = RunConfig.standard.antes
        s.round = RoundState(kind: .boss, target: 10, framesTotal: 3)
        s.boss = .tallLips
        let (after, events) = try throwing(s, .ring10, times: 9)
        #expect(after.phase == .won)
        #expect(events.contains(.runWon))
    }
}

@Suite("Prize counter")
struct PrizeCounterTests {
    func atCounter(_ offers: [Offer], tickets: Int = 20) -> RunState {
        var s = newRun(seed: 2)
        s.tickets = tickets
        s.phase = .prizeCounter(PrizeCounter(offers: offers.map { $0 }, rerollCost: 1))
        return s
    }

    @Test func buyingACharmCostsTickets() throws {
        let s = try apply(.buy(0, target: nil), to: atCounter([.charm(.multBall)])).get().state
        #expect(s.charms == [.multBall])
        #expect(s.tickets == 20 - Charm.multBall.cost)
        guard case .prizeCounter(let c) = s.phase else { Issue.record("left counter"); return }
        #expect(c.offers == [nil])
    }

    @Test func cannotAffordIt() {
        #expect(throws: ActionError.cantAfford) {
            try apply(.buy(0, target: nil), to: atCounter([.charm(.extraBall)], tickets: 2)).get()
        }
    }

    @Test func charmSlotsAreLimited() {
        var s = atCounter([.charm(.multBall)])
        s.charms = [.luckyPenny, .ladder, .heavyHand, .gutterRat, .nearMiss]
        #expect(throws: ActionError.slotsFull) { try apply(.buy(0, target: nil), to: s).get() }
    }

    @Test func stampRewritesAHoleSymbol() throws {
        let s = try apply(.buy(0, target: .ring40), to: atCounter([.stamp(.seven)])).get().state
        #expect(s.setup.symbol(for: .ring40) == .seven)
    }

    @Test func stampNeedsATarget() {
        #expect(throws: ActionError.needsTarget) { try apply(.buy(0, target: nil), to: atCounter([.stamp(.seven)])).get() }
        #expect(throws: ActionError.needsTarget) { try apply(.buy(0, target: .gutter), to: atCounter([.stamp(.seven)])).get() }
    }

    @Test func gildAddsChipsToAHole() throws {
        let s = try apply(.buy(0, target: .ring20), to: atCounter([.gild])).get().state
        #expect(s.setup.chips(for: .ring20) == 30)
    }

    @Test func sellingAChargeRefundsHalf() throws {
        var s = atCounter([])
        s.charms = [.glassCannon]
        s = try apply(.sell(0), to: s).get().state
        #expect(s.charms.isEmpty)
        #expect(s.tickets == 20 + Charm.glassCannon.cost / 2)
    }

    @Test func rerollIsDeterministicAndGetsPricier() throws {
        let s = newRunAtCounter(seed: 3)
        let a = try apply(.reroll, to: s).get().state
        let b = try apply(.reroll, to: s).get().state
        #expect(a == b)
        guard case .prizeCounter(let c) = a.phase else { Issue.record("left counter"); return }
        #expect(c.rerollCost == 2)
    }

    func newRunAtCounter(seed: UInt64) -> RunState {
        var s = newRun(seed: seed)
        s.tickets = 10
        s.round.target = 1
        for _ in 0..<9 { s = try! apply(.throwBall(launch(for: .ring10)), to: s).get().state }
        return s
    }
}

@Suite("Power-ups and fever")
struct PowerUpTests {
    @Test func goldenBallTriplesChips() throws {
        var s = newRun(seed: 1)
        s.powerUps = [.goldenBall]
        s = try apply(.arm(0), to: s).get().state
        #expect(s.round.armed == .goldenBall)
        let (after, _) = try throwing(s, .ring30)
        #expect(after.round.currentBalls[0].chips == 90)
        #expect(after.round.armed == nil)
        #expect(after.powerUps.isEmpty)
    }

    @Test func featherBallIgnoresLips() {
        var s = newRun(seed: 1)
        s.round.armed = .feather
        #expect(table(for: s).board.lipBand == 0)
    }

    @Test func wildBallIsAClover() throws {
        var s = newRun(seed: 1)
        s.round.armed = .wildBall
        let (after, _) = try throwing(s, .ring20)
        #expect(after.round.currentBalls[0].symbol == .clover)
    }

    @Test func fullHeatLightsFeverForTheNextFrame() throws {
        var s = newRun(seed: 1)
        s.heat = RunConfig.standard.feverHeat - 1
        let (after, events) = try throwing(s, .gutter, times: 3)
        #expect(after.fever)
        #expect(events.contains(.feverLit))
        let (next, _) = try throwing(after, .ring10, times: 3)
        #expect(next.round.frames.last!.steps.contains { $0.source == .fever })
        #expect(!next.fever)
    }
}

@Suite("Difficulty")
struct DifficultyTests {
    @Test func laterAntesTightenTheTable() {
        let early = difficultyTable(ante: 1), late = difficultyTable(ante: 8)
        #expect(late.board.centerHoleRadius < early.board.centerHoleRadius)
        #expect(late.board.lipBand > early.board.lipBand)
    }

    /// The promise: harder, never impossible. At the last ante, under every
    /// boss, some aim still leaves a real power window for the 50
    /// (crosswind needs you to aim into the wind).
    @Test(arguments: Boss.allCases)
    func lastAnteIsStillPlayable(boss: Boss) {
        let t = boss.modify(difficultyTable(ante: 8))
        var best = 0.0
        for aim in stride(from: -0.8, through: 0.8, by: 0.2) {
            var hits = 0
            for i in 0...400 where simulateShot(Launch(power: Double(i) / 400, aim: aim), on: t).hole == .ring50 {
                hits += 1
            }
            best = max(best, Double(hits) / 400)
            if best >= 0.015 { break }
        }
        #expect(best >= 0.015, "best 50 window at ante 8 under \(boss): \(best)")
    }
}
