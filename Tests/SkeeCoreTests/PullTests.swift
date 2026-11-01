import Testing
@testable import SkeeCore

/// A pull whose window shows these rows, found by searching the strips:
/// tests say what the window looks like, not where the stops are.
func pull(centre: [ReelSymbol], bet: Bet = .five, free: Bool = false) -> Pull {
    let stops = (0..<3).map { reel in
        let strip = Pull.strips[reel]
        guard let stop = (0..<strip.count).first(where: { strip[($0 + 1) % strip.count] == centre[reel] }) else {
            fatalError("reel \(reel) has no \(centre[reel])")
        }
        return stop
    }
    return Pull(stops: stops, bet: bet, free: free)
}

@Suite("Pull")
struct PullTests {
    @Test func theCentreRowIsTheFramesTargets() {
        let p = pull(centre: [.bell, .x3, .bonus])
        #expect(p.centre == [.bell, .x3, .bonus])
        #expect(p.targets == [.bell, .clover, .blank])
    }

    @Test func threeAlikeOnTheCentreLinePays() {
        let p = pull(centre: [.bar, .bar, .bar], bet: .one)
        #expect(p.lineWins.first == LineWin(line: 0, symbol: .bar, chips: 60, multiplier: 1))
    }

    @Test func wildsStandInAndMultipliersMultiply() {
        #expect(Pull.lineWin([.seven, .wild, .seven], line: 0)?.chips == 100)
        #expect(Pull.lineWin([.seven, .x2, .x3], line: 0)?.chips == 600)
        #expect(Pull.lineWin([.wild, .wild, .wild], line: 0)?.symbol == .wild)
        #expect(Pull.lineWin([.seven, .bell, .seven], line: 0) == nil)
        #expect(Pull.lineWin([.bonus, .wild, .wild], line: 0) == nil)
    }

    @Test func aOneLineBetOnlyPlaysTheCentre() {
        // Same window, different bets: only bigger bets read the other lines.
        var p = Pull(stops: [0, 0, 0], bet: .one)
        #expect(p.lineWins.allSatisfy { $0.line == 0 })
        p.bet = .five
        #expect(Set(p.activeLines) == [0, 1, 2, 3, 4])
    }

    @Test func threeBonusAnywhereStartsFreeGames() {
        let p = pull(centre: [.bonus, .bonus, .bonus], bet: .one)
        #expect(p.scatters >= 3)
        #expect(p.triggersFreeGames)
    }

    @Test func jackpotsNeedMaxBetAndAPaidPull() {
        #expect(pull(centre: [.seven, .seven, .seven]).jackpot == .minor)
        #expect(pull(centre: [.seven, .seven, .seven], bet: .three).jackpot == nil)
        #expect(pull(centre: [.seven, .seven, .seven], free: true).jackpot == nil)
        #expect(pull(centre: [.diamond, .wild, .diamond]).jackpot == .major)
        #expect(pull(centre: [.wild, .wild, .wild]).jackpot == .grand)
    }

    /// The strips are tuned by measurement, so measure: free games about
    /// once a run, line wins often enough to matter, GRAND rare.
    @Test func ratesOverEveryWindow() {
        var free = 0, centreWins = 0, total = 0, grand = 0
        for a in 0..<20 { for b in 0..<20 { for c in 0..<20 {
            let p = Pull(stops: [a, b, c], bet: .five)
            total += 1
            if p.triggersFreeGames { free += 1 }
            if p.lineWins.contains(where: { $0.line == 0 }) { centreWins += 1 }
            if p.jackpot == .grand { grand += 1 }
        } } }
        let freeRate = Double(free) / Double(total), winRate = Double(centreWins) / Double(total)
        #expect(freeRate > 1.0 / 120 && freeRate < 1.0 / 40)
        #expect(winRate > 0.04 && winRate < 0.15)
        #expect(grand == 1)
    }

    @Test func progressiveMetersGrowWithTheBetAndResetOnAHit() {
        var p = Progressive()
        p.feed(.five)
        #expect(p.amount(.grand) == Progressive.seeds[.grand]! + 2 * Progressive.growth[.grand]!)
        let won = p.hit(.grand)
        #expect(won > Progressive.seeds[.grand]!)
        #expect(p.amount(.grand) == Progressive.seeds[.grand]!)
    }
}

@Suite("Pull in a run")
struct PullRunTests {
    @Test func noBallBeforeThePull() {
        let s = newRun(seed: 4)
        #expect(throws: ActionError.needsPull) { try apply(.throwBall(Launch(power: 0.6, aim: 0)), to: s).get() }
        #expect(throws: ActionError.needsPull) { try apply(.foul, to: s).get() }
    }

    @Test func thePullCostsItsBetAndSetsTheTargets() throws {
        let s0 = newRun(seed: 4)
        let step = try apply(.pull(.five), to: s0).get()
        let s = step.state
        #expect(s.tickets == s0.tickets - 2)
        #expect(s.topSlot.symbols == s.round.pull!.targets)
        #expect(step.events.first == .pulled(s.round.pull!))
        #expect(throws: ActionError.alreadyPulled) { try apply(.pull(.one), to: s).get() }
    }

    @Test func aBetYouCantAffordIsRefused() {
        var s = newRun(seed: 4)
        s.tickets = 1
        #expect(throws: ActionError.cantAfford) { try apply(.pull(.five), to: s).get() }
    }

    @Test func everyFrameNeedsANewPull() throws {
        var s = newRun(seed: 4)
        for _ in 0..<3 { s = try play(.foul, to: s).get().state }
        #expect(s.round.frames.count == 1)
        #expect(s.round.pull == nil)
    }

    @Test func lineWinsAreBankedIntoTheFrame() throws {
        var s = newRun(seed: 4)
        s.round.pull = pull(centre: [.bell, .bell, .bell], bet: .one)
        for _ in 0..<3 { s = try apply(.foul, to: s).get().state }
        let f = s.round.frames[0]
        #expect(f.steps.contains(ScoreStep(source: .pull, effect: .chips(40))))
        #expect(f.total == 40)
    }

    @Test func freeGamesAddFramesThePlayerDoesNotPull() throws {
        var s = newRun(seed: 4)
        let frames = s.round.framesTotal
        let p = pull(centre: [.bonus, .bonus, .bonus], bet: .three)
        // Pull by hand with a known window: what `spin` would do.
        s = try apply(.pull(.three), to: s).get().state
        s.round.pull = p
        s.round.freeLeft = Pull.freeGamesAwarded
        s.round.framesTotal += Pull.freeGamesAwarded
        for _ in 0..<3 { s = try apply(.foul, to: s).get().state }
        // The next frame was pulled by the machine, free, at the same bet.
        let next = try #require(s.round.pull)
        #expect(next.free && next.bet == .three)
        #expect(s.round.freeLeft == Pull.freeGamesAwarded - 1)
        #expect(s.round.framesTotal == frames + Pull.freeGamesAwarded)
    }

    @Test func aFreeGameScoresDouble() {
        let ball = BallRecord(hole: .ring10, symbol: .cherry, chips: 10)
        let f = scoreFrame([ball], context: ScoringContext(pull: pull(centre: [.lemon, .cherry, .bell], bet: .one, free: true)))
        #expect(f.steps.last == ScoreStep(source: .freeGame, effect: .timesMult(2)))
    }

    @Test func aMaxBetJackpotIsAnEvent() throws {
        // Search seeds for a pull that hits a jackpot: the reducer must say so.
        for seed in UInt64(0)..<4000 {
            var s = newRun(seed: seed)
            s.tickets = 10
            let step = try apply(.pull(.five), to: s).get()
            if let tier = step.state.round.pull?.jackpot {
                #expect(step.events.contains(.jackpot(tier)))
                #expect(step.state.stats.jackpotTiers[tier] == 1)
                return
            }
        }
        Issue.record("no jackpot in 4000 pulls")
    }
}
